package com.tutict.finalassignmentbackend.controller;

import com.tutict.finalassignmentbackend.entity.SysRequestHistory;
import com.tutict.finalassignmentbackend.service.CurrentUserTrafficSupportService;
import com.tutict.finalassignmentbackend.service.PaymentRecordService;
import com.tutict.finalassignmentbackend.service.SysRequestHistoryService;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.security.SecurityRequirement;
import io.swagger.v3.oas.annotations.tags.Tag;
import jakarta.annotation.security.RolesAllowed;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import java.util.ArrayList;
import java.util.Comparator;
import java.util.LinkedHashMap;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Optional;
import java.util.function.IntFunction;
import java.util.logging.Level;
import java.util.logging.Logger;

@RestController
@RequestMapping("/api/progress")
@Tag(name = "Progress Tracker", description = "幂等请求进度跟踪接口")
@SecurityRequirement(name = "bearerAuth")
@RolesAllowed({"SUPER_ADMIN", "ADMIN", "TRAFFIC_POLICE", "FINANCE", "APPEAL_REVIEWER"})
public class ProgressItemController {

    private static final Logger LOG = Logger.getLogger(ProgressItemController.class.getName());

    private final SysRequestHistoryService sysRequestHistoryService;
    private final CurrentUserTrafficSupportService currentUserTrafficSupportService;
    private final PaymentRecordService paymentRecordService;

    public ProgressItemController(SysRequestHistoryService sysRequestHistoryService,
                                  CurrentUserTrafficSupportService currentUserTrafficSupportService,
                                  PaymentRecordService paymentRecordService) {
        this.sysRequestHistoryService = sysRequestHistoryService;
        this.currentUserTrafficSupportService = currentUserTrafficSupportService;
        this.paymentRecordService = paymentRecordService;
    }

    @PostMapping
    @Operation(summary = "创建进度记录")
    public ResponseEntity<SysRequestHistory> create(@RequestBody SysRequestHistory request,
                                                    @RequestHeader(value = "Idempotency-Key", required = false)
                                                    String idempotencyKey) {
        return ResponseEntity.status(HttpStatus.METHOD_NOT_ALLOWED).build();
    }

    @PutMapping("/{historyId}")
    @Operation(summary = "更新进度记录")
    public ResponseEntity<SysRequestHistory> update(@PathVariable Long historyId,
                                                    @RequestBody SysRequestHistory request,
                                                    @RequestHeader(value = "Idempotency-Key", required = false)
                                                    String idempotencyKey) {
        return ResponseEntity.status(HttpStatus.METHOD_NOT_ALLOWED).build();
    }

    @DeleteMapping("/{historyId}")
    @Operation(summary = "删除进度记录")
    public ResponseEntity<Void> delete(@PathVariable Long historyId) {
        return ResponseEntity.status(HttpStatus.METHOD_NOT_ALLOWED).build();
    }

    @GetMapping("/{historyId}")
    @Operation(summary = "查询进度详情")
    public ResponseEntity<SysRequestHistory> get(@PathVariable Long historyId) {
        try {
            SysRequestHistory history = sysRequestHistoryService.findById(historyId);
            return history == null ? ResponseEntity.notFound().build() : ResponseEntity.ok(history);
        } catch (Exception ex) {
            LOG.log(Level.WARNING, "Get request history failed", ex);
            return ResponseEntity.status(resolveStatus(ex)).build();
        }
    }

    @GetMapping
    @Operation(summary = "查询全部进度记录")
    public ResponseEntity<List<SysRequestHistory>> list(@RequestParam(defaultValue = "1") int page,
                                                        @RequestParam(defaultValue = "20") int size) {
        try {
            return ResponseEntity.ok(sysRequestHistoryService.findAll(page, size));
        } catch (Exception ex) {
            LOG.log(Level.WARNING, "List request histories failed", ex);
            return ResponseEntity.status(resolveStatus(ex)).build();
        }
    }

    @GetMapping("/me")
    @RolesAllowed({"SUPER_ADMIN", "ADMIN", "TRAFFIC_POLICE", "FINANCE", "APPEAL_REVIEWER", "USER"})
    @Operation(summary = "鏌ヨ褰撳墠鐧诲綍鐢ㄦ埛杩涘害璁板綍")
    public ResponseEntity<List<SysRequestHistory>> listCurrentUserProgress(@RequestParam(defaultValue = "1") int page,
                                                                           @RequestParam(defaultValue = "20") int size) {
        try {
            Long userId = currentUserTrafficSupportService.requireCurrentUser().getUserId();
            String currentUserIdCardNumber = tryResolveCurrentUserIdCardNumber();
            LinkedHashMap<Long, SysRequestHistory> merged = new LinkedHashMap<>();
            LinkedHashMap<String, LinkedHashSet<Long>> relatedBusinessIds = new LinkedHashMap<>();
            int relatedPageSize = Math.max(size * 5, 100);
            int relatedHistoryPageSize = Math.max(size * 10, 200);
            fetchAllPages(pageNumber -> sysRequestHistoryService.findByUserId(userId, pageNumber, relatedPageSize), relatedPageSize)
                    .forEach(history -> putIfPresent(merged, history));

            LinkedHashSet<Long> businessIds = new LinkedHashSet<>();
            LinkedHashSet<Long> fineIds = new LinkedHashSet<>();
            fetchAllPages(pageNumber -> currentUserTrafficSupportService.listCurrentUserAppeals(pageNumber, relatedPageSize), relatedPageSize).stream()
                    .map(appeal -> appeal == null ? null : appeal.getAppealId())
                    .filter(id -> id != null && id > 0)
                    .forEach(id -> registerBusinessId(relatedBusinessIds, businessIds, id, "APPEAL_"));
            fetchAllPages(pageNumber -> currentUserTrafficSupportService.listCurrentUserFines(pageNumber, relatedPageSize), relatedPageSize).stream()
                    .map(fine -> fine == null ? null : fine.getFineId())
                    .filter(id -> id != null && id > 0)
                    .forEach(id -> registerBusinessId(relatedBusinessIds, businessIds, id, "FINE_"));
            relatedBusinessIds.getOrDefault("FINE_", new LinkedHashSet<>()).forEach(fineIds::add);
            fetchAllPages(pageNumber -> currentUserTrafficSupportService.listCurrentUserOffenses(pageNumber, relatedPageSize), relatedPageSize).stream()
                    .map(offense -> offense == null ? null : offense.getOffenseId())
                    .filter(id -> id != null && id > 0)
                    .forEach(id -> registerBusinessId(relatedBusinessIds, businessIds, id, "OFFENSE_"));
            fetchAllPages(pageNumber -> currentUserTrafficSupportService.listCurrentUserDeductions(pageNumber, relatedPageSize), relatedPageSize).stream()
                    .map(deduction -> deduction == null ? null : deduction.getDeductionId())
                    .filter(id -> id != null && id > 0)
                    .forEach(id -> registerBusinessId(relatedBusinessIds, businessIds, id, "DEDUCTION_"));
            if (currentUserIdCardNumber != null) {
                currentUserTrafficSupportService.listCurrentUserVehicles().stream()
                        .map(vehicle -> vehicle == null ? null : vehicle.getVehicleId())
                        .filter(id -> id != null && id > 0)
                        .forEach(id -> registerBusinessId(relatedBusinessIds, businessIds, id, "VEHICLE_"));
                fetchAllPages(pageNumber -> paymentRecordService.searchByPayerIdCard(currentUserIdCardNumber, pageNumber, relatedPageSize), relatedPageSize).stream()
                        .filter(payment -> payment != null
                                && payment.getFineId() != null
                                && fineIds.contains(payment.getFineId()))
                        .map(payment -> payment.getPaymentId())
                        .filter(id -> id != null && id > 0)
                        .forEach(id -> registerBusinessId(
                                relatedBusinessIds,
                                businessIds,
                                id,
                                "PAYMENT_",
                                "PARTIAL_REFUND",
                                "WAIVE_AND_REFUND"));
            }
            fineIds.forEach(fineId -> fetchAllPages(
                            pageNumber -> sysRequestHistoryService.findRefundAudits(null, fineId, null, pageNumber, relatedPageSize),
                            relatedPageSize)
                    .forEach(history -> putIfPresent(merged, history)));

            fetchAllPages(pageNumber -> sysRequestHistoryService.findByBusinessIds(businessIds, pageNumber, relatedHistoryPageSize),
                    relatedHistoryPageSize)
                    .forEach(history -> putIfRelatedBusinessHistory(merged, history, relatedBusinessIds));

            List<SysRequestHistory> ordered = merged.values().stream()
                    .sorted(Comparator.comparing(SysRequestHistory::getUpdatedAt,
                                    Comparator.nullsLast(Comparator.reverseOrder()))
                            .thenComparing(SysRequestHistory::getCreatedAt,
                                    Comparator.nullsLast(Comparator.reverseOrder()))
                            .thenComparing(SysRequestHistory::getId,
                                    Comparator.nullsLast(Comparator.reverseOrder())))
                    .skip((long) (Math.max(page, 1) - 1) * Math.max(size, 1))
                    .limit(Math.max(size, 1))
                    .toList();
            return ResponseEntity.ok(ordered);
        } catch (IllegalStateException ex) {
            return ResponseEntity.status(HttpStatus.UNAUTHORIZED).build();
        } catch (Exception ex) {
            LOG.log(Level.WARNING, "List current user progress failed", ex);
            return ResponseEntity.status(resolveStatus(ex)).build();
        }
    }

    @GetMapping("/status")
    @Operation(summary = "按业务状态分页查询进度")
    public ResponseEntity<List<SysRequestHistory>> listByStatus(@RequestParam String status,
                                                                @RequestParam(defaultValue = "1") int page,
                                                                @RequestParam(defaultValue = "20") int size) {
        try {
            return ResponseEntity.ok(sysRequestHistoryService.findByBusinessStatus(status, page, size));
        } catch (Exception ex) {
            LOG.log(Level.WARNING, "List request histories by status failed", ex);
            return ResponseEntity.status(resolveStatus(ex)).build();
        }
    }

    @GetMapping("/idempotency/{key}")
    @Operation(summary = "根据幂等键查询进度")
    public ResponseEntity<SysRequestHistory> getByIdempotencyKey(@PathVariable String key) {
        try {
            Optional<SysRequestHistory> history = sysRequestHistoryService.findByIdempotencyKey(key);
            return history.map(ResponseEntity::ok).orElseGet(() -> ResponseEntity.notFound().build());
        } catch (Exception ex) {
            LOG.log(Level.WARNING, "Get request history by idempotency key failed", ex);
            return ResponseEntity.status(resolveStatus(ex)).build();
        }
    }

    @GetMapping("/refunds")
    @Operation(summary = "鏌ヨ閫€娆惧璁¤褰?")
    public ResponseEntity<List<SysRequestHistory>> listRefundAudits(@RequestParam(required = false) String status,
                                                                    @RequestParam(required = false) Long fineId,
                                                                    @RequestParam(required = false) Long paymentId,
                                                                    @RequestParam(defaultValue = "1") int page,
                                                                    @RequestParam(defaultValue = "20") int size) {
        try {
            if (fineId != null || paymentId != null) {
                return ResponseEntity.ok(sysRequestHistoryService.findRefundAudits(status, fineId, paymentId, page, size));
            }
            if (status == null || status.isBlank()) {
                return ResponseEntity.ok(sysRequestHistoryService.findRefundAudits(page, size));
            }
            return ResponseEntity.ok(sysRequestHistoryService.findRefundAuditsByStatus(status, page, size));
        } catch (Exception ex) {
            LOG.log(Level.WARNING, "List refund audits failed", ex);
            return ResponseEntity.status(resolveStatus(ex)).build();
        }
    }

    private boolean hasKey(String value) {
        return value != null && !value.isBlank();
    }

    private <T> List<T> fetchAllPages(IntFunction<List<T>> pageFetcher, int pageSize) {
        List<T> allItems = new ArrayList<>();
        if (pageFetcher == null || pageSize < 1) {
            return allItems;
        }
        for (int pageNumber = 1; ; pageNumber++) {
            List<T> pageItems = pageFetcher.apply(pageNumber);
            if (pageItems == null || pageItems.isEmpty()) {
                break;
            }
            allItems.addAll(pageItems);
            if (pageItems.size() < pageSize) {
                break;
            }
        }
        return allItems;
    }

    private String tryResolveCurrentUserIdCardNumber() {
        try {
            return currentUserTrafficSupportService.getCurrentUserIdCardNumber();
        } catch (IllegalStateException ex) {
            return null;
        }
    }

    private void putIfPresent(LinkedHashMap<Long, SysRequestHistory> sink, SysRequestHistory history) {
        if (sink == null || history == null || history.getId() == null) {
            return;
        }
        sink.put(history.getId(), history);
    }

    private void putIfRelatedBusinessHistory(LinkedHashMap<Long, SysRequestHistory> sink,
                                             SysRequestHistory history,
                                             LinkedHashMap<String, LinkedHashSet<Long>> relatedBusinessIds) {
        if (!isRelatedBusinessHistory(history, relatedBusinessIds)) {
            return;
        }
        putIfPresent(sink, history);
    }

    private boolean isRelatedBusinessHistory(SysRequestHistory history,
                                             LinkedHashMap<String, LinkedHashSet<Long>> relatedBusinessIds) {
        if (history == null
                || history.getBusinessId() == null
                || history.getBusinessId() <= 0
                || relatedBusinessIds == null
                || relatedBusinessIds.isEmpty()) {
            return false;
        }
        String businessType = normalizeBusinessType(history.getBusinessType());
        if (businessType.isEmpty()) {
            return false;
        }
        for (var entry : relatedBusinessIds.entrySet()) {
            if (businessType.startsWith(entry.getKey()) && entry.getValue().contains(history.getBusinessId())) {
                return true;
            }
        }
        return false;
    }

    private void registerBusinessId(LinkedHashMap<String, LinkedHashSet<Long>> relatedBusinessIds,
                                    LinkedHashSet<Long> businessIds,
                                    Long businessId,
                                    String... businessTypePrefixes) {
        if (businessId == null || businessId <= 0) {
            return;
        }
        if (businessIds != null) {
            businessIds.add(businessId);
        }
        if (relatedBusinessIds == null || businessTypePrefixes == null) {
            return;
        }
        for (String businessTypePrefix : businessTypePrefixes) {
            String normalizedPrefix = normalizeBusinessType(businessTypePrefix);
            if (normalizedPrefix.isEmpty()) {
                continue;
            }
            relatedBusinessIds.computeIfAbsent(normalizedPrefix, ignored -> new LinkedHashSet<>()).add(businessId);
        }
    }

    private String normalizeBusinessType(String businessType) {
        if (businessType == null) {
            return "";
        }
        return businessType.trim().toUpperCase();
    }

    private HttpStatus resolveStatus(Exception ex) {
        return (ex instanceof IllegalArgumentException || ex instanceof IllegalStateException)
                ? HttpStatus.BAD_REQUEST
                : HttpStatus.INTERNAL_SERVER_ERROR;
    }
}
