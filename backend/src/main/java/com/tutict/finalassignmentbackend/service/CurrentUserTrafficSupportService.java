package com.tutict.finalassignmentbackend.service;

import com.tutict.finalassignmentbackend.config.statemachine.events.AppealAcceptanceEvent;
import com.tutict.finalassignmentbackend.config.statemachine.states.AppealAcceptanceState;
import com.tutict.finalassignmentbackend.entity.AppealRecord;
import com.tutict.finalassignmentbackend.entity.DeductionRecord;
import com.tutict.finalassignmentbackend.entity.DriverInformation;
import com.tutict.finalassignmentbackend.entity.FineRecord;
import com.tutict.finalassignmentbackend.entity.OffenseRecord;
import com.tutict.finalassignmentbackend.entity.PaymentRecord;
import com.tutict.finalassignmentbackend.entity.SysUser;
import com.tutict.finalassignmentbackend.entity.VehicleInformation;
import com.tutict.finalassignmentbackend.service.statemachine.StateMachineService;
import org.springframework.security.authentication.AnonymousAuthenticationToken;
import org.springframework.security.core.Authentication;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.LocalDateTime;
import java.util.ArrayList;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Objects;
import java.util.Set;
import java.util.regex.Pattern;

@Service
public class CurrentUserTrafficSupportService {

    private static final Pattern EMAIL_PATTERN =
            Pattern.compile("^[\\w.%+-]+@[\\w.-]+\\.[A-Za-z]{2,}$");
    private static final Pattern CONTACT_PATTERN = Pattern.compile("^1\\d{10}$");
    private static final Pattern ID_CARD_PATTERN =
            Pattern.compile("^(\\d{15}|\\d{17}[\\dXx])$");
    private static final Pattern DRIVER_LICENSE_PATTERN = Pattern.compile("^\\d{12}$");

    private final SysUserService sysUserService;
    private final DriverInformationService driverInformationService;
    private final OffenseRecordService offenseRecordService;
    private final FineRecordService fineRecordService;
    private final DeductionRecordService deductionRecordService;
    private final VehicleInformationService vehicleInformationService;
    private final AppealRecordService appealRecordService;
    private final PaymentRecordService paymentRecordService;
    private final StateMachineService stateMachineService;

    public CurrentUserTrafficSupportService(SysUserService sysUserService,
                                           DriverInformationService driverInformationService,
                                           OffenseRecordService offenseRecordService,
                                           FineRecordService fineRecordService,
                                           DeductionRecordService deductionRecordService,
                                           VehicleInformationService vehicleInformationService,
                                           AppealRecordService appealRecordService,
                                           PaymentRecordService paymentRecordService,
                                           StateMachineService stateMachineService) {
        this.sysUserService = sysUserService;
        this.driverInformationService = driverInformationService;
        this.offenseRecordService = offenseRecordService;
        this.fineRecordService = fineRecordService;
        this.deductionRecordService = deductionRecordService;
        this.vehicleInformationService = vehicleInformationService;
        this.appealRecordService = appealRecordService;
        this.paymentRecordService = paymentRecordService;
        this.stateMachineService = stateMachineService;
    }

    public SysUser requireCurrentUser() {
        Authentication authentication = SecurityContextHolder.getContext().getAuthentication();
        if (authentication == null
                || !authentication.isAuthenticated()
                || authentication instanceof AnonymousAuthenticationToken) {
            throw new IllegalStateException("Current user is not authenticated");
        }
        SysUser user = sysUserService.findByUsername(authentication.getName());
        if (user == null) {
            throw new IllegalStateException("Current user not found");
        }
        return user;
    }

    public DriverInformation getCurrentDriver() {
        return resolveCurrentDriver();
    }

    public String getCurrentUserIdCardNumber() {
        return requireCurrentUserIdCardNumber();
    }

    @Transactional
    public SysUser updateCurrentUserProfile(SysUser draft) {
        SysUser currentUser = requireCurrentUser();
        DriverInformation currentDriver = resolveCurrentDriver();
        if (draft == null) {
            throw new IllegalArgumentException("Current user draft must not be null");
        }

        currentUser.setRealName(firstNonBlank(trimToNull(draft.getRealName()), currentUser.getRealName()));
        currentUser.setContactNumber(firstNonBlank(trimToNull(draft.getContactNumber()), currentUser.getContactNumber()));
        currentUser.setGender(firstNonBlank(trimToNull(draft.getGender()), currentUser.getGender()));
        currentUser.setEmail(firstNonBlank(trimToNull(draft.getEmail()), currentUser.getEmail()));
        currentUser.setRemarks(firstNonBlank(trimToNull(draft.getRemarks()), currentUser.getRemarks()));
        currentUser.setUpdatedAt(LocalDateTime.now());

        validateSelfServiceProfile(currentUser, currentDriver);
        SysUser updatedUser = sysUserService.updateSysUser(currentUser);
        syncExistingDriverProfile(updatedUser, currentDriver);
        return updatedUser;
    }

    @Transactional
    public DriverInformation saveCurrentDriver(DriverInformation draft) {
        SysUser user = requireCurrentUser();
        DriverInformation existing = resolveCurrentDriver();
        String previousIdCardNumber = firstNonBlank(
                trimToNull(existing == null ? null : existing.getIdCardNumber()),
                trimToNull(user.getIdCardNumber()));
        DriverInformation merged = existing == null ? new DriverInformation() : existing;
        merged.setName(firstNonBlank(trimToNull(draft == null ? null : draft.getName()),
                existing == null ? null : existing.getName(),
                user.getRealName(),
                user.getUsername()));
        merged.setContactNumber(firstNonBlank(trimToNull(draft == null ? null : draft.getContactNumber()),
                existing == null ? null : existing.getContactNumber(),
                user.getContactNumber()));
        merged.setIdCardNumber(firstNonBlank(trimToNull(draft == null ? null : draft.getIdCardNumber()),
                existing == null ? null : existing.getIdCardNumber(),
                user.getIdCardNumber()));
        merged.setDriverLicenseNumber(firstNonBlank(
                trimToNull(draft == null ? null : draft.getDriverLicenseNumber()),
                existing == null ? null : existing.getDriverLicenseNumber()));
        merged.setGender(firstNonBlank(trimToNull(draft == null ? null : draft.getGender()),
                existing == null ? null : existing.getGender(),
                user.getGender()));
        merged.setEmail(firstNonBlank(trimToNull(draft == null ? null : draft.getEmail()),
                existing == null ? null : existing.getEmail(),
                user.getEmail()));
        merged.setAddress(firstNonBlank(trimToNull(draft == null ? null : draft.getAddress()),
                existing == null ? null : existing.getAddress()));
        merged.setLicenseType(firstNonBlank(trimToNull(draft == null ? null : draft.getLicenseType()),
                existing == null ? null : existing.getLicenseType()));
        merged.setIssuingAuthority(firstNonBlank(trimToNull(draft == null ? null : draft.getIssuingAuthority()),
                existing == null ? null : existing.getIssuingAuthority()));
        merged.setStatus(firstNonBlank(existing == null ? null : existing.getStatus()));
        merged.setBirthdate(firstNonNull(draft == null ? null : draft.getBirthdate(),
                existing == null ? null : existing.getBirthdate()));
        merged.setFirstLicenseDate(firstNonNull(draft == null ? null : draft.getFirstLicenseDate(),
                existing == null ? null : existing.getFirstLicenseDate()));
        merged.setIssueDate(firstNonNull(draft == null ? null : draft.getIssueDate(),
                existing == null ? null : existing.getIssueDate()));
        merged.setExpiryDate(firstNonNull(draft == null ? null : draft.getExpiryDate(),
                existing == null ? null : existing.getExpiryDate()));
        merged.setCurrentPoints(existing == null ? null : existing.getCurrentPoints());
        merged.setTotalDeductedPoints(existing == null ? null : existing.getTotalDeductedPoints());
        merged.setUpdatedAt(LocalDateTime.now());

        validateSelfServiceProfile(user, merged);
        requireStableDriverLink(existing, merged);
        syncCurrentUserProfile(user, merged, previousIdCardNumber);

        if (existing == null) {
            merged.setCreatedAt(LocalDateTime.now());
            return driverInformationService.createDriver(merged);
        }
        return driverInformationService.updateDriver(merged);
    }

    public List<OffenseRecord> listCurrentUserOffenses(int page, int size) {
        return offenseRecordService.findByDriverIds(new ArrayList<>(resolveCandidateDriverIds()), page, size);
    }

    public List<FineRecord> listCurrentUserFines(int page, int size) {
        List<Long> offenseIds = resolveCurrentUserOffenseIds();
        if (offenseIds.isEmpty()) {
            return List.of();
        }
        return fineRecordService.findByOffenseIds(offenseIds, page, size);
    }

    public List<AppealRecord> listCurrentUserAppeals(int page, int size) {
        List<Long> offenseIds = resolveCurrentUserOffenseIds();
        if (offenseIds.isEmpty()) {
            return List.of();
        }
        return appealRecordService.findByOffenseIds(offenseIds, page, size);
    }

    public List<DeductionRecord> listCurrentUserDeductions(int page, int size) {
        return deductionRecordService.findByDriverIds(new ArrayList<>(resolveCandidateDriverIds()), page, size);
    }

    @Transactional
    public PaymentRecord createPaymentForCurrentUser(PaymentRecord draft) {
        Objects.requireNonNull(draft, "Payment record cannot be null");
        SysUser user = requireCurrentUser();
        DriverInformation driver = resolveCurrentDriver();
        Long fineId = draft.getFineId();
        if (fineId == null || fineId <= 0) {
            throw new IllegalArgumentException("Fine ID must be greater than zero");
        }
        FineRecord fineRecord = fineRecordService.findById(fineId);
        if (fineRecord == null) {
            throw new IllegalStateException("Fine record not found");
        }
        OffenseRecord offense = offenseRecordService.findById(fineRecord.getOffenseId());
        if (offense == null || !resolveCandidateDriverIds().contains(offense.getDriverId())) {
            throw new IllegalStateException("Fine does not belong to current user");
        }

        draft.setPayerName(firstNonBlank(
                driver == null ? null : driver.getName(),
                user.getRealName(),
                user.getUsername()));
        draft.setPayerIdCard(requireCurrentUserIdCardNumber(user, driver));
        draft.setPayerContact(firstNonBlank(
                driver == null ? null : driver.getContactNumber(),
                user.getContactNumber()));
        draft.setPaymentChannel(firstNonBlank(trimToNull(draft.getPaymentChannel()), "USER_SELF_SERVICE"));
        draft.setPaymentMethod(firstNonBlank(trimToNull(draft.getPaymentMethod()), "WeChat"));
        draft.setRemarks(firstNonBlank(trimToNull(draft.getRemarks()), "Current user self-service payment"));
        draft.setPaymentStatus(null);
        draft.setRefundAmount(null);
        draft.setRefundTime(null);
        return paymentRecordService.createPaymentRecord(draft);
    }

    public List<VehicleInformation> listCurrentUserVehicles() {
        return vehicleInformationService.getVehicleInformationByIdCardNumber(requireCurrentUserIdCardNumber());
    }

    @Transactional
    public VehicleInformation createVehicleForCurrentUser(VehicleInformation draft) {
        Objects.requireNonNull(draft, "Vehicle information cannot be null");
        SysUser user = requireCurrentUser();
        DriverInformation driver = resolveCurrentDriver();
        String ownerIdCardNumber = requireCurrentUserIdCardNumber(user, driver);

        ensureCurrentUserOwnsVehicleDraft(draft.getOwnerIdCard(), ownerIdCardNumber);
        draft.setOwnerIdCard(ownerIdCardNumber);
        draft.setOwnerName(resolveCurrentOwnerName(user, driver, null));
        draft.setOwnerContact(resolveCurrentOwnerContact(user, driver, null));
        draft.setUpdatedAt(LocalDateTime.now());
        return vehicleInformationService.createVehicleInformation(draft);
    }

    @Transactional
    public VehicleInformation updateVehicleForCurrentUser(Long vehicleId, VehicleInformation draft) {
        Objects.requireNonNull(draft, "Vehicle information cannot be null");
        SysUser user = requireCurrentUser();
        DriverInformation driver = resolveCurrentDriver();
        VehicleInformation existingVehicle = requireCurrentUserVehicle(vehicleId);
        String ownerIdCardNumber = firstNonBlank(trimToNull(existingVehicle.getOwnerIdCard()),
                requireCurrentUserIdCardNumber(user, driver));

        ensureCurrentUserOwnsVehicleDraft(draft.getOwnerIdCard(), ownerIdCardNumber);
        draft.setVehicleId(vehicleId);
        draft.setOwnerIdCard(ownerIdCardNumber);
        draft.setOwnerName(resolveCurrentOwnerName(user, driver, existingVehicle));
        draft.setOwnerContact(resolveCurrentOwnerContact(user, driver, existingVehicle));
        draft.setUpdatedAt(LocalDateTime.now());
        return vehicleInformationService.updateVehicleInformation(draft);
    }

    @Transactional
    public void deleteVehicleForCurrentUser(Long vehicleId) {
        VehicleInformation vehicle = requireCurrentUserVehicle(vehicleId);
        vehicleInformationService.deleteVehicleInformation(vehicle.getVehicleId());
    }

    public List<String> getCurrentUserVehiclePlateSuggestions(String prefix, int size) {
        return vehicleInformationService.getLicensePlateAutocompleteSuggestions(
                prefix, size, requireCurrentUserIdCardNumber());
    }

    public List<String> getCurrentUserVehicleTypeSuggestions(String prefix, int size) {
        return vehicleInformationService.getVehicleTypeAutocompleteSuggestions(
                requireCurrentUserIdCardNumber(), prefix, size);
    }

    public AppealRecord createAppealForCurrentUser(AppealRecord appealRecord) {
        Objects.requireNonNull(appealRecord, "Appeal record cannot be null");
        SysUser user = requireCurrentUser();
        if (appealRecord.getOffenseId() == null) {
            throw new IllegalArgumentException("Offense ID must not be empty");
        }
        OffenseRecord offense = offenseRecordService.findById(appealRecord.getOffenseId());
        if (offense == null) {
            throw new IllegalStateException("Offense not found");
        }
        if (!resolveCandidateDriverIds().contains(offense.getDriverId())) {
            throw new IllegalStateException("Offense does not belong to current user");
        }

        DriverInformation driver = resolveCurrentDriver();
        appealRecord.setAppellantName(firstNonBlank(
                driver == null ? null : driver.getName(),
                user.getRealName(),
                user.getUsername()));
        appealRecord.setAppellantIdCard(firstNonBlank(
                driver == null ? null : driver.getIdCardNumber(),
                user.getIdCardNumber()));
        appealRecord.setAppellantContact(firstNonBlank(
                driver == null ? null : driver.getContactNumber(),
                user.getContactNumber()));
        appealRecord.setAppellantEmail(firstNonBlank(
                driver == null ? null : driver.getEmail(),
                user.getEmail()));
        return appealRecordService.createAppeal(appealRecord);
    }

    @Transactional
    public AppealRecord triggerCurrentUserAppealAcceptanceEvent(Long appealId, AppealAcceptanceEvent event) {
        if (appealId == null || appealId <= 0) {
            throw new IllegalArgumentException("Appeal ID must be greater than zero");
        }
        if (event == null) {
            throw new IllegalArgumentException("Appeal acceptance event must not be empty");
        }
        ensureCurrentUserCanTriggerAcceptanceEvent(event);
        AppealRecord appeal = requireCurrentUserAppeal(appealId);
        AppealAcceptanceState currentState = resolveAppealAcceptanceState(appeal.getAcceptanceStatus());
        AppealAcceptanceState newState =
                stateMachineService.processAppealAcceptanceState(appealId, currentState, event);
        if (newState == currentState) {
            throw new IllegalStateException("Appeal acceptance state does not allow this event");
        }
        return appealRecordService.updateAcceptanceStatus(appealId, newState);
    }

    private DriverInformation resolveCurrentDriver() {
        return driverInformationService.findLinkedDriverForUser(requireCurrentUser());
    }

    private AppealRecord requireCurrentUserAppeal(Long appealId) {
        AppealRecord appeal = appealRecordService.getAppealById(appealId);
        if (appeal == null) {
            throw new IllegalStateException("Appeal not found");
        }
        if (appeal.getOffenseId() == null) {
            throw new IllegalStateException("Appeal offense does not belong to current user");
        }
        Long offenseId = appeal.getOffenseId();
        if (!resolveCurrentUserOffenseIds().contains(offenseId)) {
            throw new IllegalStateException("Appeal does not belong to current user");
        }
        return appeal;
    }

    private void ensureCurrentUserCanTriggerAcceptanceEvent(AppealAcceptanceEvent event) {
        if (event != AppealAcceptanceEvent.SUPPLEMENT_COMPLETE
                && event != AppealAcceptanceEvent.RESUBMIT) {
            throw new IllegalArgumentException("Current user can only complete supplements or resubmit appeals");
        }
    }

    private AppealAcceptanceState resolveAppealAcceptanceState(String code) {
        AppealAcceptanceState state = AppealAcceptanceState.fromCode(code);
        return state != null ? state : AppealAcceptanceState.PENDING;
    }

    private VehicleInformation requireCurrentUserVehicle(Long vehicleId) {
        if (vehicleId == null || vehicleId <= 0) {
            throw new IllegalArgumentException("Vehicle ID must be greater than zero");
        }
        VehicleInformation vehicle = vehicleInformationService.getVehicleInformationById(vehicleId);
        if (vehicle == null) {
            throw new IllegalStateException("Vehicle not found");
        }
        String ownerIdCardNumber = trimToNull(vehicle.getOwnerIdCard());
        if (!Objects.equals(ownerIdCardNumber, requireCurrentUserIdCardNumber())) {
            throw new IllegalStateException("Vehicle does not belong to current user");
        }
        return vehicle;
    }

    private Set<Long> resolveCandidateDriverIds() {
        Set<Long> candidateIds = new LinkedHashSet<>();
        DriverInformation driver = resolveCurrentDriver();
        if (driver != null && driver.getDriverId() != null) {
            candidateIds.add(driver.getDriverId());
        }
        return candidateIds;
    }

    private List<Long> resolveCurrentUserOffenseIds() {
        return offenseRecordService.findIdsByDriverIds(new ArrayList<>(resolveCandidateDriverIds()));
    }

    private String firstNonBlank(String... candidates) {
        if (candidates == null) {
            return null;
        }
        for (String candidate : candidates) {
            if (candidate != null && !candidate.isBlank()) {
                return candidate;
            }
        }
        return null;
    }

    private <T> T firstNonNull(T... candidates) {
        if (candidates == null) {
            return null;
        }
        for (T candidate : candidates) {
            if (candidate != null) {
                return candidate;
            }
        }
        return null;
    }

    private String requireCurrentUserIdCardNumber() {
        return requireCurrentUserIdCardNumber(requireCurrentUser(), resolveCurrentDriver());
    }

    private String requireCurrentUserIdCardNumber(SysUser user, DriverInformation driver) {
        String idCardNumber = firstNonBlank(
                trimToNull(driver == null ? null : driver.getIdCardNumber()),
                trimToNull(user == null ? null : user.getIdCardNumber()));
        if (idCardNumber == null) {
            throw new IllegalStateException("Current user profile has no ID card number");
        }
        return idCardNumber;
    }

    private void ensureCurrentUserOwnsVehicleDraft(String ownerIdCardNumber, String currentUserIdCardNumber) {
        String normalizedOwnerIdCard = trimToNull(ownerIdCardNumber);
        if (normalizedOwnerIdCard == null) {
            return;
        }
        if (!Objects.equals(normalizedOwnerIdCard, currentUserIdCardNumber)) {
            throw new IllegalStateException("Vehicle owner ID card is outside the current user scope");
        }
    }

    private String resolveCurrentOwnerName(SysUser user, DriverInformation driver, VehicleInformation existingVehicle) {
        return firstNonBlank(
                trimToNull(driver == null ? null : driver.getName()),
                trimToNull(user == null ? null : user.getRealName()),
                trimToNull(user == null ? null : user.getUsername()),
                trimToNull(existingVehicle == null ? null : existingVehicle.getOwnerName()));
    }

    private String resolveCurrentOwnerContact(SysUser user, DriverInformation driver, VehicleInformation existingVehicle) {
        return firstNonBlank(
                trimToNull(driver == null ? null : driver.getContactNumber()),
                trimToNull(user == null ? null : user.getContactNumber()),
                trimToNull(existingVehicle == null ? null : existingVehicle.getOwnerContact()));
    }

    private void syncCurrentUserProfile(SysUser user, DriverInformation driver, String previousIdCardNumber) {
        if (user == null || driver == null) {
            return;
        }
        String nextIdCardNumber = firstNonBlank(driver.getIdCardNumber(), user.getIdCardNumber());
        user.setRealName(firstNonBlank(driver.getName(), user.getRealName()));
        user.setIdCardNumber(nextIdCardNumber);
        user.setContactNumber(firstNonBlank(driver.getContactNumber(), user.getContactNumber()));
        user.setGender(firstNonBlank(driver.getGender(), user.getGender()));
        user.setEmail(firstNonBlank(driver.getEmail(), user.getEmail()));
        user.setUpdatedAt(LocalDateTime.now());
        sysUserService.updateSysUser(user);
        if (!Objects.equals(trimToNull(previousIdCardNumber), trimToNull(nextIdCardNumber))) {
            vehicleInformationService.reassignOwnerIdCard(
                    previousIdCardNumber,
                    nextIdCardNumber,
                    firstNonBlank(driver.getName(), user.getRealName(), user.getUsername()),
                    firstNonBlank(driver.getContactNumber(), user.getContactNumber()));
        }
    }

    private void syncExistingDriverProfile(SysUser user, DriverInformation driver) {
        if (driver == null) {
            return;
        }
        driver.setName(firstNonBlank(user.getRealName(), driver.getName(), user.getUsername()));
        driver.setContactNumber(firstNonBlank(user.getContactNumber(), driver.getContactNumber()));
        driver.setGender(firstNonBlank(user.getGender(), driver.getGender()));
        driver.setEmail(firstNonBlank(user.getEmail(), driver.getEmail()));
        driver.setUpdatedAt(LocalDateTime.now());
        driverInformationService.updateDriver(driver);
    }

    private String trimToNull(String value) {
        if (value == null) {
            return null;
        }
        String normalized = value.trim();
        return normalized.isEmpty() ? null : normalized;
    }

    private void requireStableDriverLink(DriverInformation existing, DriverInformation merged) {
        if (existing != null) {
            return;
        }
        if (trimToNull(merged == null ? null : merged.getIdCardNumber()) == null) {
            throw new IllegalArgumentException("ID card number is required to create a driver profile.");
        }
    }

    private void validateSelfServiceProfile(SysUser user, DriverInformation driver) {
        String realName = firstNonBlank(
                trimToNull(driver == null ? null : driver.getName()),
                trimToNull(user == null ? null : user.getRealName()));
        String contactNumber = firstNonBlank(
                trimToNull(driver == null ? null : driver.getContactNumber()),
                trimToNull(user == null ? null : user.getContactNumber()));
        String idCardNumber = firstNonBlank(
                trimToNull(driver == null ? null : driver.getIdCardNumber()),
                trimToNull(user == null ? null : user.getIdCardNumber()));
        String email = firstNonBlank(
                trimToNull(driver == null ? null : driver.getEmail()),
                trimToNull(user == null ? null : user.getEmail()));
        String driverLicenseNumber = trimToNull(driver == null ? null : driver.getDriverLicenseNumber());

        if (realName != null && (realName.length() < 2 || realName.length() > 50)) {
            throw new IllegalArgumentException("Name must be between 2 and 50 characters.");
        }
        if (contactNumber != null && !CONTACT_PATTERN.matcher(contactNumber).matches()) {
            throw new IllegalArgumentException("Enter a valid 11-digit phone number.");
        }
        if (idCardNumber != null && !ID_CARD_PATTERN.matcher(idCardNumber).matches()) {
            throw new IllegalArgumentException("Enter a valid ID card number (15 or 18 digits).");
        }
        if (email != null && !EMAIL_PATTERN.matcher(email).matches()) {
            throw new IllegalArgumentException("Enter a valid email address.");
        }
        if (driverLicenseNumber != null && !DRIVER_LICENSE_PATTERN.matcher(driverLicenseNumber).matches()) {
            throw new IllegalArgumentException("Enter a valid 12-digit driver license number.");
        }

        ensureUniqueEmail(user, email);
        ensureUniqueIdCard(user, driver, idCardNumber);
        ensureUniqueDriverLicense(driver);
    }

    private void ensureUniqueEmail(SysUser user, String effectiveEmail) {
        String email = trimToNull(effectiveEmail);
        if (email == null) {
            return;
        }
        SysUser existingUser = sysUserService.findByExactEmail(email);
        if (existingUser != null && !Objects.equals(existingUser.getUserId(), user.getUserId())) {
            throw new IllegalArgumentException("Email already exists.");
        }
    }

    private void ensureUniqueIdCard(SysUser user, DriverInformation driver, String effectiveIdCardNumber) {
        String idCardNumber = trimToNull(effectiveIdCardNumber);
        if (idCardNumber == null) {
            return;
        }
        SysUser existingUser = sysUserService.findByExactIdCardNumber(idCardNumber);
        if (existingUser != null && !Objects.equals(existingUser.getUserId(), user.getUserId())) {
            throw new IllegalArgumentException("ID card number already exists.");
        }
        DriverInformation existingDriver = driverInformationService.findByExactIdCardNumber(idCardNumber);
        Long currentDriverId = driver == null ? null : driver.getDriverId();
        if (existingDriver != null && !Objects.equals(existingDriver.getDriverId(), currentDriverId)) {
            throw new IllegalArgumentException("ID card number already exists.");
        }
    }

    private void ensureUniqueDriverLicense(DriverInformation driver) {
        String driverLicenseNumber = trimToNull(driver == null ? null : driver.getDriverLicenseNumber());
        if (driverLicenseNumber == null) {
            return;
        }
        DriverInformation existingDriver = driverInformationService.findByExactDriverLicenseNumber(driverLicenseNumber);
        if (existingDriver != null && !Objects.equals(existingDriver.getDriverId(), driver.getDriverId())) {
            throw new IllegalArgumentException("Driver license number already exists.");
        }
    }
}
