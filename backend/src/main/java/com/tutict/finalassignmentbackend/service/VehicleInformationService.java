package com.tutict.finalassignmentbackend.service;

import com.baomidou.mybatisplus.extension.plugins.pagination.Page;
import com.baomidou.mybatisplus.core.conditions.query.QueryWrapper;
import com.tutict.finalassignmentbackend.config.websocket.WsAction;
import com.tutict.finalassignmentbackend.entity.DriverVehicle;
import com.tutict.finalassignmentbackend.entity.OffenseRecord;
import com.tutict.finalassignmentbackend.entity.SysRequestHistory;
import com.tutict.finalassignmentbackend.entity.VehicleInformation;
import com.tutict.finalassignmentbackend.entity.elastic.VehicleInformationDocument;
import com.tutict.finalassignmentbackend.mapper.DriverVehicleMapper;
import com.tutict.finalassignmentbackend.mapper.OffenseRecordMapper;
import com.tutict.finalassignmentbackend.mapper.SysRequestHistoryMapper;
import com.tutict.finalassignmentbackend.mapper.VehicleInformationMapper;
import com.tutict.finalassignmentbackend.repository.VehicleInformationSearchRepository;
import jakarta.servlet.http.HttpServletRequest;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.cache.annotation.CacheEvict;
import org.springframework.cache.annotation.Cacheable;
import org.springframework.data.domain.PageRequest;
import org.springframework.data.domain.Pageable;
import org.springframework.data.elasticsearch.core.SearchHit;
import org.springframework.data.elasticsearch.core.SearchHits;
import org.springframework.kafka.core.KafkaTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.transaction.support.TransactionSynchronization;
import org.springframework.transaction.support.TransactionSynchronizationManager;
import org.springframework.web.context.request.RequestAttributes;
import org.springframework.web.context.request.RequestContextHolder;
import org.springframework.web.context.request.ServletRequestAttributes;

import java.net.URLDecoder;
import java.nio.charset.StandardCharsets;
import java.time.LocalDateTime;
import java.util.*;
import java.util.logging.Level;
import java.util.logging.Logger;
import java.util.stream.Collectors;
import java.util.stream.StreamSupport;

@Service
public class VehicleInformationService {

    private static final Logger log = Logger.getLogger(VehicleInformationService.class.getName());
    private static final String CACHE_NAME = "vehicleCache";

    private final VehicleInformationMapper vehicleInformationMapper;
    private final DriverVehicleMapper driverVehicleMapper;
    private final OffenseRecordMapper offenseRecordMapper;
    private final SysRequestHistoryMapper sysRequestHistoryMapper;
    private final KafkaTemplate<String, VehicleInformation> kafkaTemplate;
    private final VehicleInformationSearchRepository vehicleInformationSearchRepository;

    @Autowired
    public VehicleInformationService(VehicleInformationMapper vehicleInformationMapper,
                                     DriverVehicleMapper driverVehicleMapper,
                                     OffenseRecordMapper offenseRecordMapper,
                                     SysRequestHistoryMapper sysRequestHistoryMapper,
                                     KafkaTemplate<String, VehicleInformation> kafkaTemplate,
                                     VehicleInformationSearchRepository vehicleInformationSearchRepository) {
        this.vehicleInformationMapper = vehicleInformationMapper;
        this.driverVehicleMapper = driverVehicleMapper;
        this.offenseRecordMapper = offenseRecordMapper;
        this.sysRequestHistoryMapper = sysRequestHistoryMapper;
        this.kafkaTemplate = kafkaTemplate;
        this.vehicleInformationSearchRepository = vehicleInformationSearchRepository;
    }

    @Transactional
    @CacheEvict(cacheNames = CACHE_NAME, allEntries = true)
    @WsAction(service = "VehicleInformationService", action = "checkAndInsertIdempotency")
    public void checkAndInsertIdempotency(String idempotencyKey, VehicleInformation vehicleInformation, String action) {
        Objects.requireNonNull(vehicleInformation, "Vehicle information cannot be null");
        SysRequestHistory existing = sysRequestHistoryMapper.selectByIdempotencyKey(idempotencyKey);
        if (existing != null) {
            log.warning(() -> String.format("Duplicate vehicle request detected (key=%s)", idempotencyKey));
            throw new RuntimeException("Duplicate vehicle request detected");
        }

        SysRequestHistory history = buildHistory(idempotencyKey, vehicleInformation, action);
        sysRequestHistoryMapper.insert(history);

        sendKafkaMessage(action, idempotencyKey, vehicleInformation);
    }

    @Transactional
    @CacheEvict(cacheNames = CACHE_NAME, allEntries = true)
    public VehicleInformation createVehicleInformation(VehicleInformation vehicleInformation) {
        validateVehicle(vehicleInformation);
        vehicleInformationMapper.insert(vehicleInformation);
        syncToIndexAfterCommit(vehicleInformation);
        return vehicleInformation;
    }

    @Transactional
    @CacheEvict(cacheNames = CACHE_NAME, allEntries = true)
    @WsAction(service = "VehicleInformationService", action = "updateVehicleInformation")
    public VehicleInformation updateVehicleInformation(VehicleInformation vehicleInformation) {
        validateVehicleId(vehicleInformation);
        int rows = vehicleInformationMapper.updateById(vehicleInformation);
        if (rows == 0) {
            throw new IllegalStateException("Vehicle not found with ID: " + vehicleInformation.getVehicleId());
        }
        syncToIndexAfterCommit(vehicleInformation);
        return vehicleInformation;
    }

    @Transactional
    @CacheEvict(cacheNames = CACHE_NAME, allEntries = true)
    public void deleteVehicleInformation(long vehicleId) {
        validateVehicleId(vehicleId);
        ensureVehicleCanBeDeleted(vehicleId);
        int rows = vehicleInformationMapper.deleteById(vehicleId);
        if (rows == 0) {
            throw new IllegalStateException("Vehicle not found with ID: " + vehicleId);
        }
        syncDeleteAfterCommit(vehicleId);
    }

    @Transactional
    @CacheEvict(cacheNames = CACHE_NAME, allEntries = true)
    public void deleteVehicleInformationByLicensePlate(String licensePlate) {
        validateInput(licensePlate, "Invalid license plate");
        QueryWrapper<VehicleInformation> wrapper = new QueryWrapper<>();
        wrapper.eq("license_plate", licensePlate);
        List<VehicleInformation> vehicles = vehicleInformationMapper.selectList(wrapper);
        if (vehicles.isEmpty()) {
            return;
        }
        for (VehicleInformation vehicle : vehicles) {
            if (vehicle != null && vehicle.getVehicleId() != null) {
                ensureVehicleCanBeDeleted(vehicle.getVehicleId());
            }
        }
        vehicleInformationMapper.delete(wrapper);
        runAfterCommitOrNow(() -> vehicles.stream()
                .map(VehicleInformation::getVehicleId)
                .filter(Objects::nonNull)
                .forEach(vehicleInformationSearchRepository::deleteById));
    }

    @Cacheable(cacheNames = CACHE_NAME, key = "#vehicleId", unless = "#result == null")
    @WsAction(service = "VehicleInformationService", action = "getVehicleInformationById")
    public VehicleInformation getVehicleInformationById(long vehicleId) {
        validateVehicleId(vehicleId);
        return vehicleInformationSearchRepository.findById(vehicleId)
                .map(VehicleInformationDocument::toEntity)
                .orElseGet(() -> {
                    VehicleInformation entity = vehicleInformationMapper.selectById(vehicleId);
                    if (entity != null) {
                        vehicleInformationSearchRepository.save(VehicleInformationDocument.fromEntity(entity));
                    }
                    return entity;
                });
    }

    @Cacheable(cacheNames = CACHE_NAME, key = "'all'", unless = "#result == null || #result.isEmpty()")
    @WsAction(service = "VehicleInformationService", action = "getAllVehicleInformation")
    public List<VehicleInformation> getAllVehicleInformation() {
        List<VehicleInformation> fromIndex = StreamSupport.stream(
                        vehicleInformationSearchRepository.findAll().spliterator(), false)
                .map(VehicleInformationDocument::toEntity)
                .collect(Collectors.toList());
        if (!fromIndex.isEmpty()) {
            return fromIndex;
        }
        List<VehicleInformation> db = vehicleInformationMapper.selectList(null);
        syncBatchToIndexAfterCommit(db);
        return db;
    }

    @Cacheable(cacheNames = CACHE_NAME, key = "'page:' + #page + ':' + #size")
    public List<VehicleInformation> listVehicles(int page, int size) {
        validatePagination(page, size);
        QueryWrapper<VehicleInformation> wrapper = new QueryWrapper<>();
        wrapper.orderByDesc("updated_at")
                .orderByDesc("vehicle_id");
        return fetchFromDatabase(wrapper, page, size);
    }

    public boolean shouldSkipProcessing(String idempotencyKey) {
        SysRequestHistory history = sysRequestHistoryMapper.selectByIdempotencyKey(idempotencyKey);
        return history != null
                && "SUCCESS".equalsIgnoreCase(history.getBusinessStatus())
                && history.getBusinessId() != null
                && history.getBusinessId() > 0;
    }

    public void markHistorySuccess(String idempotencyKey, Long vehicleId) {
        SysRequestHistory history = sysRequestHistoryMapper.selectByIdempotencyKey(idempotencyKey);
        if (history == null) {
            log.log(Level.WARNING, "Cannot mark success for missing idempotency key {0}", idempotencyKey);
            return;
        }
        history.setBusinessStatus("SUCCESS");
        history.setBusinessId(vehicleId);
        history.setUpdatedAt(LocalDateTime.now());
        sysRequestHistoryMapper.updateById(history);
    }

    public void markHistoryFailure(String idempotencyKey, String reason) {
        SysRequestHistory history = sysRequestHistoryMapper.selectByIdempotencyKey(idempotencyKey);
        if (history == null) {
            log.log(Level.WARNING, "Cannot mark failure for missing idempotency key {0}", idempotencyKey);
            return;
        }
        history.setBusinessStatus("FAILED");
        history.setRequestParams(appendFailureReason(history.getRequestParams(), reason));
        history.setUpdatedAt(LocalDateTime.now());
        sysRequestHistoryMapper.updateById(history);
    }

    @Cacheable(cacheNames = CACHE_NAME, key = "'plate:' + #licensePlate")
    public VehicleInformation getVehicleInformationByLicensePlate(String licensePlate) {
        validateInput(licensePlate, "Invalid license plate");
        QueryWrapper<VehicleInformation> wrapper = new QueryWrapper<>();
        wrapper.eq("license_plate", licensePlate);
        VehicleInformation entity = vehicleInformationMapper.selectOne(wrapper);
        if (entity != null) {
            vehicleInformationSearchRepository.save(VehicleInformationDocument.fromEntity(entity));
        }
        return entity;
    }

    @Cacheable(cacheNames = CACHE_NAME, key = "'license:global:' + #prefix + ':' + #maxSuggestions")
    public List<String> getVehicleInformationByLicensePlateGlobally(String prefix, int maxSuggestions) {
        validateInput(prefix, "Invalid license plate prefix");
        Pageable pageable = PageRequest.of(0, Math.max(maxSuggestions, 1));
        SearchHits<VehicleInformationDocument> hits = vehicleInformationSearchRepository
                .findCompletionSuggestionsGlobally(prefix, pageable);
        return mapLicensePlateSuggestions(hits);
    }

    @Cacheable(cacheNames = CACHE_NAME, key = "'type:' + #vehicleType")
    public List<VehicleInformation> getVehicleInformationByType(String vehicleType) {
        validateInput(vehicleType, "Invalid vehicle type");
        QueryWrapper<VehicleInformation> wrapper = new QueryWrapper<>();
        wrapper.eq("vehicle_type", vehicleType);
        return vehicleInformationMapper.selectList(wrapper);
    }

    @Cacheable(cacheNames = CACHE_NAME, key = "'owner:' + #ownerName")
    public List<VehicleInformation> getVehicleInformationByOwnerName(String ownerName) {
        validateInput(ownerName, "Invalid owner name");
        QueryWrapper<VehicleInformation> wrapper = new QueryWrapper<>();
        wrapper.eq("owner_name", ownerName);
        return vehicleInformationMapper.selectList(wrapper);
    }

    @Cacheable(cacheNames = CACHE_NAME, key = "'idcard:' + #idCardNumber")
    public List<VehicleInformation> getVehicleInformationByIdCardNumber(String idCardNumber) {
        validateInput(idCardNumber, "Invalid ID card number");
        QueryWrapper<VehicleInformation> wrapper = new QueryWrapper<>();
        wrapper.eq("owner_id_card", idCardNumber);
        return vehicleInformationMapper.selectList(wrapper);
    }

    @Transactional
    @CacheEvict(cacheNames = CACHE_NAME, allEntries = true)
    public void reassignOwnerIdCard(String previousIdCardNumber,
                                    String nextIdCardNumber,
                                    String ownerName,
                                    String ownerContact) {
        if (isBlank(previousIdCardNumber)
                || isBlank(nextIdCardNumber)
                || previousIdCardNumber.trim().equals(nextIdCardNumber.trim())) {
            return;
        }
        QueryWrapper<VehicleInformation> wrapper = new QueryWrapper<>();
        wrapper.eq("owner_id_card", previousIdCardNumber.trim())
                .orderByDesc("updated_at")
                .orderByDesc("vehicle_id");
        List<VehicleInformation> vehicles = vehicleInformationMapper.selectList(wrapper);
        if (vehicles.isEmpty()) {
            return;
        }
        List<VehicleInformation> updatedVehicles = new ArrayList<>();
        LocalDateTime now = LocalDateTime.now();
        for (VehicleInformation vehicle : vehicles) {
            if (vehicle == null || vehicle.getVehicleId() == null) {
                continue;
            }
            vehicle.setOwnerIdCard(nextIdCardNumber.trim());
            if (!isBlank(ownerName)) {
                vehicle.setOwnerName(ownerName.trim());
            }
            if (!isBlank(ownerContact)) {
                vehicle.setOwnerContact(ownerContact.trim());
            }
            vehicle.setUpdatedAt(now);
            vehicleInformationMapper.updateById(vehicle);
            updatedVehicles.add(vehicle);
        }
        syncBatchToIndexAfterCommit(updatedVehicles);
    }

    @Cacheable(cacheNames = CACHE_NAME, key = "'status:' + #status")
    public List<VehicleInformation> getVehicleInformationByStatus(String status) {
        validateInput(status, "Invalid status");
        QueryWrapper<VehicleInformation> wrapper = new QueryWrapper<>();
        wrapper.eq("status", status);
        return vehicleInformationMapper.selectList(wrapper);
    }

    @Cacheable(cacheNames = CACHE_NAME, key = "'ownerNameSearch:' + #ownerName + ':' + #page + ':' + #size")
    public List<VehicleInformation> searchByOwnerName(String ownerName, int page, int size) {
        validateInput(ownerName, "Invalid owner name");
        validatePagination(page, size);
        SearchHits<VehicleInformationDocument> hits = vehicleInformationSearchRepository
                .searchByOwnerName(ownerName, pageable(page, size));
        List<VehicleInformation> fromIndex = mapVehicleHits(hits);
        if (!fromIndex.isEmpty()) {
            return fromIndex;
        }
        QueryWrapper<VehicleInformation> wrapper = new QueryWrapper<>();
        wrapper.likeRight("owner_name", ownerName)
                .orderByDesc("updated_at")
                .orderByDesc("vehicle_id");
        return fetchFromDatabase(wrapper, page, size);
    }

    @Cacheable(cacheNames = CACHE_NAME, key = "'ownerIdCardSearch:' + #ownerIdCard + ':' + #page + ':' + #size")
    public List<VehicleInformation> searchByOwnerIdCard(String ownerIdCard, int page, int size) {
        validateInput(ownerIdCard, "Invalid owner id card");
        validatePagination(page, size);
        SearchHits<VehicleInformationDocument> hits = vehicleInformationSearchRepository
                .searchByOwnerIdCard(ownerIdCard, pageable(page, size));
        List<VehicleInformation> fromIndex = mapVehicleHits(hits);
        if (!fromIndex.isEmpty()) {
            return fromIndex;
        }
        QueryWrapper<VehicleInformation> wrapper = new QueryWrapper<>();
        wrapper.eq("owner_id_card", ownerIdCard)
                .orderByDesc("updated_at")
                .orderByDesc("vehicle_id");
        return fetchFromDatabase(wrapper, page, size);
    }

    @Cacheable(cacheNames = CACHE_NAME, key = "'statusSearch:' + #status + ':' + #page + ':' + #size")
    public List<VehicleInformation> searchByStatus(String status, int page, int size) {
        validateInput(status, "Invalid status");
        validatePagination(page, size);
        SearchHits<VehicleInformationDocument> hits = vehicleInformationSearchRepository
                .searchByStatus(status, pageable(page, size));
        List<VehicleInformation> fromIndex = mapVehicleHits(hits);
        if (!fromIndex.isEmpty()) {
            return fromIndex;
        }
        QueryWrapper<VehicleInformation> wrapper = new QueryWrapper<>();
        wrapper.eq("status", status)
                .orderByDesc("updated_at")
                .orderByDesc("vehicle_id");
        return fetchFromDatabase(wrapper, page, size);
    }

    @Cacheable(cacheNames = CACHE_NAME, key = "'search:' + #query + ':' + #page + ':' + #size")
    public List<VehicleInformation> searchVehicles(String query, int page, int size) {
        validatePagination(page, size);
        if (query == null || query.trim().isEmpty()) {
            return Collections.emptyList();
        }
        QueryWrapper<VehicleInformation> wrapper = new QueryWrapper<>();
        wrapper.lambda()
                .like(VehicleInformation::getLicensePlate, query)
                .or()
                .like(VehicleInformation::getOwnerName, query)
                .or()
                .like(VehicleInformation::getVehicleType, query)
                .or()
                .like(VehicleInformation::getBrand, query);
        List<VehicleInformation> list = vehicleInformationMapper.selectList(wrapper);
        int fromIndex = Math.min((page - 1) * size, list.size());
        int toIndex = Math.min(fromIndex + size, list.size());
        return list.subList(fromIndex, toIndex);
    }

    @Cacheable(cacheNames = CACHE_NAME, key = "'autocomplete:me:' + #idCardNumber + ':' + #prefix + ':' + #maxSuggestions")
    public List<String> getLicensePlateAutocompleteSuggestions(String prefix, int maxSuggestions, String idCardNumber) {
        validateInput(idCardNumber, "Invalid ID card number");
        validateInput(prefix, "Invalid license plate prefix");
        Pageable pageable = PageRequest.of(0, Math.max(maxSuggestions, 1));
        SearchHits<VehicleInformationDocument> hits = vehicleInformationSearchRepository
                .findCompletionSuggestions(idCardNumber, prefix, pageable);
        return mapLicensePlateSuggestions(hits);
    }

    @Cacheable(cacheNames = CACHE_NAME, key = "'autocomplete:type:me:' + #idCardNumber + ':' + #prefix + ':' + #maxSuggestions")
    public List<String> getVehicleTypeAutocompleteSuggestions(String idCardNumber, String prefix, int maxSuggestions) {
        validateInput(idCardNumber, "Invalid ID card number");
        validateInput(prefix, "Invalid vehicle type prefix");
        Pageable pageable = PageRequest.of(0, Math.max(maxSuggestions, 1));
        SearchHits<VehicleInformationDocument> hits = vehicleInformationSearchRepository
                .searchByVehicleTypePrefix(prefix, idCardNumber, pageable);
        return mapVehicleTypeSuggestions(hits);
    }

    @Cacheable(cacheNames = CACHE_NAME, key = "'autocomplete:type:global:' + #prefix + ':' + #maxSuggestions")
    public List<String> getVehicleTypesByPrefixGlobally(String prefix, int maxSuggestions) {
        validateInput(prefix, "Invalid vehicle type prefix");
        QueryWrapper<VehicleInformation> wrapper = new QueryWrapper<>();
        wrapper.select("DISTINCT vehicle_type").like("vehicle_type", prefix);
        List<VehicleInformation> result = vehicleInformationMapper.selectList(wrapper);
        return result.stream()
                .map(VehicleInformation::getVehicleType)
                .filter(Objects::nonNull)
                .map(type -> URLDecoder.decode(type, StandardCharsets.UTF_8))
                .limit(Math.max(maxSuggestions, 1))
                .collect(Collectors.toList());
    }

    @Cacheable(cacheNames = CACHE_NAME, key = "'exists:' + #licensePlate")
    public boolean isLicensePlateExists(String licensePlate) {
        validateInput(licensePlate, "Invalid license plate");
        QueryWrapper<VehicleInformation> wrapper = new QueryWrapper<>();
        wrapper.eq("license_plate", licensePlate);
        return vehicleInformationMapper.selectCount(wrapper) > 0;
    }

    private List<String> mapLicensePlateSuggestions(SearchHits<VehicleInformationDocument> hits) {
        if (hits == null || !hits.hasSearchHits()) {
            return Collections.emptyList();
        }
        return hits.getSearchHits().stream()
                .map(SearchHit::getContent)
                .map(VehicleInformationDocument::getLicensePlate)
                .filter(Objects::nonNull)
                .map(plate -> URLDecoder.decode(plate, StandardCharsets.UTF_8))
                .distinct()
                .collect(Collectors.toList());
    }

    private List<String> mapVehicleTypeSuggestions(SearchHits<VehicleInformationDocument> hits) {
        if (hits == null || !hits.hasSearchHits()) {
            return Collections.emptyList();
        }
        return hits.getSearchHits().stream()
                .map(SearchHit::getContent)
                .map(VehicleInformationDocument::getVehicleType)
                .filter(Objects::nonNull)
                .map(type -> URLDecoder.decode(type, StandardCharsets.UTF_8))
                .distinct()
                .collect(Collectors.toList());
    }

    private List<VehicleInformation> mapVehicleHits(SearchHits<VehicleInformationDocument> hits) {
        if (hits == null || !hits.hasSearchHits()) {
            return Collections.emptyList();
        }
        return hits.getSearchHits().stream()
                .map(SearchHit::getContent)
                .map(VehicleInformationDocument::toEntity)
                .collect(Collectors.toList());
    }

    private Pageable pageable(int page, int size) {
        return PageRequest.of(Math.max(page - 1, 0), Math.max(size, 1));
    }

    private List<VehicleInformation> fetchFromDatabase(QueryWrapper<VehicleInformation> wrapper, int page, int size) {
        Page<VehicleInformation> mpPage = new Page<>(Math.max(page, 1), Math.max(size, 1));
        vehicleInformationMapper.selectPage(mpPage, wrapper);
        List<VehicleInformation> records = mpPage.getRecords();
        syncBatchToIndexAfterCommit(records);
        return records;
    }

    private SysRequestHistory buildHistory(String idempotencyKey, VehicleInformation vehicleInformation, String action) {
        SysRequestHistory history = new SysRequestHistory();
        history.setIdempotencyKey(idempotencyKey);
        history.setRequestMethod(resolveRequestMethod("POST"));
        history.setRequestUrl(resolveRequestUrl("/api/vehicles"));
        history.setRequestParams(buildRequestParams(vehicleInformation));
        history.setBusinessType(resolveBusinessType(action));
        history.setBusinessStatus("PROCESSING");
        history.setRequestIp(resolveRequestIp());
        history.setCreatedAt(LocalDateTime.now());
        history.setUpdatedAt(LocalDateTime.now());
        return history;
    }

    private String buildRequestParams(VehicleInformation vehicleInformation) {
        if (vehicleInformation == null) {
            return null;
        }
        StringBuilder builder = new StringBuilder();
        appendParam(builder, "licensePlate", vehicleInformation.getLicensePlate());
        appendParam(builder, "vehicleType", vehicleInformation.getVehicleType());
        appendParam(builder, "ownerName", vehicleInformation.getOwnerName());
        appendParam(builder, "ownerIdCard", vehicleInformation.getOwnerIdCard());
        appendParam(builder, "status", vehicleInformation.getStatus());
        return truncate(builder.toString());
    }

    private String resolveBusinessType(String action) {
        String normalized = isBlank(action) ? "CREATE" : action.trim().toUpperCase(Locale.ROOT);
        return "VEHICLE_" + normalized;
    }

    private void appendParam(StringBuilder builder, String key, Object value) {
        if (builder == null || value == null) {
            return;
        }
        String normalized = value.toString().trim();
        if (normalized.isEmpty()) {
            return;
        }
        if (!builder.isEmpty()) {
            builder.append(',');
        }
        builder.append(key).append('=').append(normalized);
    }

    private String appendFailureReason(String existing, String reason) {
        String normalizedReason = truncate(reason);
        if (isBlank(normalizedReason)) {
            return existing;
        }
        if (isBlank(existing)) {
            return "failure=" + normalizedReason;
        }
        return truncate(existing + ",failure=" + normalizedReason);
    }

    private void syncToIndexAfterCommit(VehicleInformation vehicleInformation) {
        if (vehicleInformation == null) {
            return;
        }
        runAfterCommitOrNow(() -> {
            VehicleInformationDocument doc = VehicleInformationDocument.fromEntity(vehicleInformation);
            if (doc != null) {
                vehicleInformationSearchRepository.save(doc);
            }
        });
    }

    private void syncBatchToIndexAfterCommit(List<VehicleInformation> vehicles) {
        if (vehicles == null || vehicles.isEmpty()) {
            return;
        }
        runAfterCommitOrNow(() -> {
            List<VehicleInformationDocument> documents = vehicles.stream()
                    .filter(Objects::nonNull)
                    .map(VehicleInformationDocument::fromEntity)
                    .filter(Objects::nonNull)
                    .collect(Collectors.toList());
            if (!documents.isEmpty()) {
                vehicleInformationSearchRepository.saveAll(documents);
            }
        });
    }

    private void syncDeleteAfterCommit(Long vehicleId) {
        runAfterCommitOrNow(() -> vehicleInformationSearchRepository.deleteById(vehicleId));
    }

    private void sendKafkaMessage(String action, String idempotencyKey, VehicleInformation vehicleInformation) {
        String topic = "vehicle_" + action.toLowerCase(Locale.ROOT);
        try {
            kafkaTemplate.send(topic, idempotencyKey, vehicleInformation);
        } catch (Exception e) {
            log.log(Level.WARNING, "Failed to send vehicle Kafka message", e);
        }
    }

    private String resolveRequestMethod(String fallback) {
        RequestAttributes requestAttributes = RequestContextHolder.getRequestAttributes();
        if (!(requestAttributes instanceof ServletRequestAttributes servletRequestAttributes)) {
            return fallback;
        }
        HttpServletRequest request = servletRequestAttributes.getRequest();
        if (request == null || isBlank(request.getMethod())) {
            return fallback;
        }
        return request.getMethod().trim().toUpperCase(Locale.ROOT);
    }

    private String resolveRequestUrl(String fallback) {
        RequestAttributes requestAttributes = RequestContextHolder.getRequestAttributes();
        if (!(requestAttributes instanceof ServletRequestAttributes servletRequestAttributes)) {
            return fallback;
        }
        HttpServletRequest request = servletRequestAttributes.getRequest();
        if (request == null || isBlank(request.getRequestURI())) {
            return fallback;
        }
        return request.getRequestURI().trim();
    }

    private String resolveRequestIp() {
        RequestAttributes requestAttributes = RequestContextHolder.getRequestAttributes();
        if (!(requestAttributes instanceof ServletRequestAttributes servletRequestAttributes)) {
            return null;
        }
        HttpServletRequest request = servletRequestAttributes.getRequest();
        if (request == null) {
            return null;
        }
        String forwardedFor = request.getHeader("X-Forwarded-For");
        if (!isBlank(forwardedFor)) {
            return forwardedFor.split(",")[0].trim();
        }
        String realIp = request.getHeader("X-Real-IP");
        if (!isBlank(realIp)) {
            return realIp.trim();
        }
        String remoteAddr = request.getRemoteAddr();
        return isBlank(remoteAddr) ? null : remoteAddr.trim();
    }

    private void validateVehicle(VehicleInformation vehicleInformation) {
        if (vehicleInformation == null) {
            throw new IllegalArgumentException("Vehicle information cannot be null");
        }
        validateInput(vehicleInformation.getLicensePlate(), "License plate cannot be empty");
        ensureUniqueLicensePlate(vehicleInformation);
        ensureUniqueEngineNumber(vehicleInformation);
        ensureUniqueFrameNumber(vehicleInformation);
    }

    private void validateVehicleId(VehicleInformation vehicleInformation) {
        validateVehicle(vehicleInformation);
        validateVehicleId(vehicleInformation.getVehicleId());
    }

    private void validateVehicleId(Long vehicleId) {
        if (vehicleId == null || vehicleId <= 0) {
            throw new IllegalArgumentException("Invalid vehicle ID: " + vehicleId);
        }
    }

    private void validatePagination(int page, int size) {
        if (page < 1 || size < 1) {
            throw new IllegalArgumentException("Page must be >= 1 and size must be >= 1");
        }
    }

    private boolean isBlank(String value) {
        return value == null || value.trim().isEmpty();
    }

    private String truncate(String value) {
        if (value == null) {
            return null;
        }
        return value.length() <= 500 ? value : value.substring(0, 500);
    }

    private void runAfterCommitOrNow(Runnable task) {
        if (task == null) {
            return;
        }
        if (TransactionSynchronizationManager.isSynchronizationActive()) {
            TransactionSynchronizationManager.registerSynchronization(new TransactionSynchronization() {
                @Override
                public void afterCommit() {
                    task.run();
                }
            });
            return;
        }
        task.run();
    }

    private void validateInput(String value, String message) {
        if (value == null || value.trim().isEmpty()) {
            throw new IllegalArgumentException(message);
        }
    }

    private void ensureUniqueLicensePlate(VehicleInformation vehicleInformation) {
        QueryWrapper<VehicleInformation> wrapper = new QueryWrapper<>();
        wrapper.eq("license_plate", vehicleInformation.getLicensePlate().trim());
        if (vehicleInformation.getVehicleId() != null) {
            wrapper.ne("vehicle_id", vehicleInformation.getVehicleId());
        }
        if (vehicleInformationMapper.selectCount(wrapper) > 0) {
            throw new IllegalArgumentException("License plate already exists");
        }
    }

    private void ensureUniqueEngineNumber(VehicleInformation vehicleInformation) {
        if (vehicleInformation == null
                || vehicleInformation.getEngineNumber() == null
                || vehicleInformation.getEngineNumber().trim().isEmpty()) {
            return;
        }
        QueryWrapper<VehicleInformation> wrapper = new QueryWrapper<>();
        wrapper.eq("engine_number", vehicleInformation.getEngineNumber().trim());
        if (vehicleInformation.getVehicleId() != null) {
            wrapper.ne("vehicle_id", vehicleInformation.getVehicleId());
        }
        if (vehicleInformationMapper.selectCount(wrapper) > 0) {
            throw new IllegalArgumentException("Engine number already exists");
        }
    }

    private void ensureUniqueFrameNumber(VehicleInformation vehicleInformation) {
        if (vehicleInformation == null
                || vehicleInformation.getFrameNumber() == null
                || vehicleInformation.getFrameNumber().trim().isEmpty()) {
            return;
        }
        QueryWrapper<VehicleInformation> wrapper = new QueryWrapper<>();
        wrapper.eq("frame_number", vehicleInformation.getFrameNumber().trim());
        if (vehicleInformation.getVehicleId() != null) {
            wrapper.ne("vehicle_id", vehicleInformation.getVehicleId());
        }
        if (vehicleInformationMapper.selectCount(wrapper) > 0) {
            throw new IllegalArgumentException("Frame number already exists");
        }
    }

    private void ensureVehicleCanBeDeleted(Long vehicleId) {
        QueryWrapper<DriverVehicle> bindingWrapper = new QueryWrapper<>();
        bindingWrapper.eq("vehicle_id", vehicleId);
        if (driverVehicleMapper.selectCount(bindingWrapper) > 0) {
            throw new IllegalStateException("Cannot delete vehicle while driver bindings still exist");
        }

        QueryWrapper<OffenseRecord> offenseWrapper = new QueryWrapper<>();
        offenseWrapper.eq("vehicle_id", vehicleId);
        if (offenseRecordMapper.selectCount(offenseWrapper) > 0) {
            throw new IllegalStateException("Cannot delete vehicle while offense records still exist");
        }
    }
}
