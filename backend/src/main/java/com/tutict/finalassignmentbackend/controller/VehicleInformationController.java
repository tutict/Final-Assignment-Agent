package com.tutict.finalassignmentbackend.controller;

import com.tutict.finalassignmentbackend.entity.DriverVehicle;
import com.tutict.finalassignmentbackend.entity.VehicleInformation;
import com.tutict.finalassignmentbackend.service.CurrentUserTrafficSupportService;
import com.tutict.finalassignmentbackend.service.DriverVehicleService;
import com.tutict.finalassignmentbackend.service.VehicleInformationService;
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

import java.util.List;
import java.util.Map;
import java.util.logging.Level;
import java.util.logging.Logger;

@RestController
@RequestMapping("/api/vehicles")
@Tag(name = "Vehicle Information", description = "Vehicle Information endpoints")
@SecurityRequirement(name = "bearerAuth")
@RolesAllowed({"SUPER_ADMIN", "ADMIN", "TRAFFIC_POLICE"})
public class VehicleInformationController {

    private static final Logger LOG = Logger.getLogger(VehicleInformationController.class.getName());

    private final VehicleInformationService vehicleInformationService;
    private final DriverVehicleService driverVehicleService;
    private final CurrentUserTrafficSupportService currentUserTrafficSupportService;

    public VehicleInformationController(VehicleInformationService vehicleInformationService,
                                        DriverVehicleService driverVehicleService,
                                        CurrentUserTrafficSupportService currentUserTrafficSupportService) {
        this.vehicleInformationService = vehicleInformationService;
        this.driverVehicleService = driverVehicleService;
        this.currentUserTrafficSupportService = currentUserTrafficSupportService;
    }

    @GetMapping("/me")
    @RolesAllowed({"SUPER_ADMIN", "ADMIN", "TRAFFIC_POLICE", "USER"})
    @Operation(summary = "List Current User Vehicles")
    public ResponseEntity<List<VehicleInformation>> listCurrentUserVehicles() {
        try {
            return ResponseEntity.ok(currentUserTrafficSupportService.listCurrentUserVehicles());
        } catch (IllegalStateException ex) {
            return ResponseEntity.status(HttpStatus.FORBIDDEN).build();
        } catch (Exception ex) {
            LOG.log(Level.WARNING, "List current user vehicles failed", ex);
            return ResponseEntity.status(resolveStatus(ex)).build();
        }
    }

    @PostMapping("/me")
    @RolesAllowed({"SUPER_ADMIN", "ADMIN", "TRAFFIC_POLICE", "USER"})
    @Operation(summary = "Create Current User Vehicle")
    public ResponseEntity<VehicleInformation> createCurrentUserVehicle(@RequestBody VehicleInformation request) {
        try {
            return ResponseEntity.status(HttpStatus.CREATED)
                    .body(currentUserTrafficSupportService.createVehicleForCurrentUser(request));
        } catch (IllegalStateException ex) {
            return ResponseEntity.status(HttpStatus.FORBIDDEN).build();
        } catch (Exception ex) {
            LOG.log(Level.WARNING, "Create current user vehicle failed", ex);
            return ResponseEntity.status(resolveStatus(ex)).build();
        }
    }

    @PutMapping("/me/{vehicleId}")
    @RolesAllowed({"SUPER_ADMIN", "ADMIN", "TRAFFIC_POLICE", "USER"})
    @Operation(summary = "Update Current User Vehicle")
    public ResponseEntity<VehicleInformation> updateCurrentUserVehicle(@PathVariable Long vehicleId,
                                                                       @RequestBody VehicleInformation request) {
        try {
            return ResponseEntity.ok(currentUserTrafficSupportService.updateVehicleForCurrentUser(vehicleId, request));
        } catch (IllegalStateException ex) {
            return ResponseEntity.status(HttpStatus.FORBIDDEN).build();
        } catch (Exception ex) {
            LOG.log(Level.WARNING, "Update current user vehicle failed", ex);
            return ResponseEntity.status(resolveStatus(ex)).build();
        }
    }

    @DeleteMapping("/me/{vehicleId}")
    @RolesAllowed({"SUPER_ADMIN", "ADMIN", "TRAFFIC_POLICE", "USER"})
    @Operation(summary = "Delete Current User Vehicle")
    public ResponseEntity<Void> deleteCurrentUserVehicle(@PathVariable Long vehicleId) {
        try {
            currentUserTrafficSupportService.deleteVehicleForCurrentUser(vehicleId);
            return ResponseEntity.noContent().build();
        } catch (IllegalStateException ex) {
            return ResponseEntity.status(HttpStatus.FORBIDDEN).build();
        } catch (Exception ex) {
            LOG.log(Level.WARNING, "Delete current user vehicle failed", ex);
            return ResponseEntity.status(resolveStatus(ex)).build();
        }
    }

    @PostMapping
    @Operation(summary = "Create Vehicle")
    public ResponseEntity<VehicleInformation> createVehicle(@RequestBody VehicleInformation request,
                                                            @RequestHeader(value = "Idempotency-Key", required = false)
                                                            String idempotencyKey) {
        boolean useKey = hasKey(idempotencyKey);
        try {
            if (useKey) {
                if (vehicleInformationService.shouldSkipProcessing(idempotencyKey)) {
                    return ResponseEntity.status(HttpStatus.ALREADY_REPORTED).build();
                }
                vehicleInformationService.checkAndInsertIdempotency(idempotencyKey, request, "create");
            }
            VehicleInformation saved = vehicleInformationService.createVehicleInformation(request);
            if (useKey && saved.getVehicleId() != null) {
                vehicleInformationService.markHistorySuccess(idempotencyKey, saved.getVehicleId());
            }
            return ResponseEntity.status(HttpStatus.CREATED).body(saved);
        } catch (Exception ex) {
            if (useKey) {
                vehicleInformationService.markHistoryFailure(idempotencyKey, ex.getMessage());
            }
            LOG.log(Level.SEVERE, "Create vehicle failed", ex);
            return ResponseEntity.status(resolveStatus(ex)).build();
        }
    }

    @PutMapping("/{vehicleId}")
    @Operation(summary = "Update Vehicle")
    public ResponseEntity<VehicleInformation> updateVehicle(@PathVariable Long vehicleId,
                                                            @RequestBody VehicleInformation request,
                                                            @RequestHeader(value = "Idempotency-Key", required = false)
                                                            String idempotencyKey) {
        boolean useKey = hasKey(idempotencyKey);
        try {
            request.setVehicleId(vehicleId);
            if (useKey) {
                if (vehicleInformationService.shouldSkipProcessing(idempotencyKey)) {
                    return ResponseEntity.status(HttpStatus.ALREADY_REPORTED).build();
                }
                vehicleInformationService.checkAndInsertIdempotency(idempotencyKey, request, "update");
            }
            VehicleInformation updated = vehicleInformationService.updateVehicleInformation(request);
            if (useKey && updated.getVehicleId() != null) {
                vehicleInformationService.markHistorySuccess(idempotencyKey, updated.getVehicleId());
            }
            return ResponseEntity.ok(updated);
        } catch (Exception ex) {
            if (useKey) {
                vehicleInformationService.markHistoryFailure(idempotencyKey, ex.getMessage());
            }
            LOG.log(Level.SEVERE, "Update vehicle failed", ex);
            return ResponseEntity.status(resolveStatus(ex)).build();
        }
    }

    @DeleteMapping("/{vehicleId}")
    @Operation(summary = "Delete Vehicle")
    public ResponseEntity<Void> deleteVehicle(@PathVariable Long vehicleId) {
        try {
            vehicleInformationService.deleteVehicleInformation(vehicleId);
            return ResponseEntity.noContent().build();
        } catch (Exception ex) {
            LOG.log(Level.WARNING, "Delete vehicle failed", ex);
            return ResponseEntity.status(resolveStatus(ex)).build();
        }
    }

    @DeleteMapping("/license/{licensePlate}")
    @Operation(summary = "Delete Vehicle By License")
    public ResponseEntity<Void> deleteVehicleByLicense(@PathVariable String licensePlate) {
        try {
            vehicleInformationService.deleteVehicleInformationByLicensePlate(licensePlate);
            return ResponseEntity.noContent().build();
        } catch (Exception ex) {
            LOG.log(Level.WARNING, "Delete vehicle by license failed", ex);
            return ResponseEntity.status(resolveStatus(ex)).build();
        }
    }

    @GetMapping("/{vehicleId}")
    @Operation(summary = "Get Vehicle")
    public ResponseEntity<VehicleInformation> getVehicle(@PathVariable Long vehicleId) {
        try {
            VehicleInformation vehicle = vehicleInformationService.getVehicleInformationById(vehicleId);
            return vehicle == null ? ResponseEntity.notFound().build() : ResponseEntity.ok(vehicle);
        } catch (Exception ex) {
            LOG.log(Level.WARNING, "Get vehicle failed", ex);
            return ResponseEntity.status(resolveStatus(ex)).build();
        }
    }

    @GetMapping
    @Operation(summary = "List Vehicles")
    public ResponseEntity<List<VehicleInformation>> listVehicles(@RequestParam(defaultValue = "1") int page,
                                                                 @RequestParam(defaultValue = "20") int size) {
        try {
            return ResponseEntity.ok(vehicleInformationService.listVehicles(page, size));
        } catch (Exception ex) {
            LOG.log(Level.WARNING, "List vehicles failed", ex);
            return ResponseEntity.status(resolveStatus(ex)).build();
        }
    }

    @GetMapping("/search/license")
    @Operation(summary = "Search By License")
    @RolesAllowed({"SUPER_ADMIN", "ADMIN", "TRAFFIC_POLICE", "FINANCE"})
    public ResponseEntity<VehicleInformation> searchByLicense(@RequestParam String licensePlate) {
        try {
            VehicleInformation vehicle = vehicleInformationService.getVehicleInformationByLicensePlate(licensePlate);
            return vehicle == null ? ResponseEntity.notFound().build() : ResponseEntity.ok(vehicle);
        } catch (Exception ex) {
            LOG.log(Level.WARNING, "Search vehicle by license failed", ex);
            return ResponseEntity.status(resolveStatus(ex)).build();
        }
    }

    @GetMapping("/search/owner")
    @Operation(summary = "Search By Owner Id Card")
    public ResponseEntity<List<VehicleInformation>> searchByOwnerIdCard(@RequestParam String idCard,
                                                                        @RequestParam(defaultValue = "1") int page,
                                                                        @RequestParam(defaultValue = "20") int size) {
        try {
            return ResponseEntity.ok(vehicleInformationService.searchByOwnerIdCard(idCard, page, size));
        } catch (Exception ex) {
            LOG.log(Level.WARNING, "Search vehicle by id card failed", ex);
            return ResponseEntity.status(resolveStatus(ex)).build();
        }
    }

    @GetMapping("/search/type")
    @Operation(summary = "Search By Type")
    public ResponseEntity<List<VehicleInformation>> searchByType(@RequestParam String type) {
        try {
            return ResponseEntity.ok(vehicleInformationService.getVehicleInformationByType(type));
        } catch (Exception ex) {
            LOG.log(Level.WARNING, "Search vehicle by type failed", ex);
            return ResponseEntity.status(resolveStatus(ex)).build();
        }
    }

    @GetMapping("/search/owner/name")
    @Operation(summary = "Search By Owner Name")
    public ResponseEntity<List<VehicleInformation>> searchByOwnerName(@RequestParam String ownerName,
                                                                      @RequestParam(defaultValue = "1") int page,
                                                                      @RequestParam(defaultValue = "20") int size) {
        try {
            return ResponseEntity.ok(vehicleInformationService.searchByOwnerName(ownerName, page, size));
        } catch (Exception ex) {
            LOG.log(Level.WARNING, "Search vehicle by owner name failed", ex);
            return ResponseEntity.status(resolveStatus(ex)).build();
        }
    }

    @GetMapping("/search/status")
    @Operation(summary = "Search By Status")
    public ResponseEntity<List<VehicleInformation>> searchByStatus(@RequestParam String status,
                                                                   @RequestParam(defaultValue = "1") int page,
                                                                   @RequestParam(defaultValue = "20") int size) {
        try {
            return ResponseEntity.ok(vehicleInformationService.searchByStatus(status, page, size));
        } catch (Exception ex) {
            LOG.log(Level.WARNING, "Search vehicle by status failed", ex);
            return ResponseEntity.status(resolveStatus(ex)).build();
        }
    }

    @GetMapping("/search/general")
    @Operation(summary = "Search Vehicles")
    public ResponseEntity<List<VehicleInformation>> searchVehicles(@RequestParam String keywords,
                                                                   @RequestParam(defaultValue = "1") int page,
                                                                   @RequestParam(defaultValue = "20") int size) {
        try {
            return ResponseEntity.ok(vehicleInformationService.searchVehicles(keywords, page, size));
        } catch (Exception ex) {
            LOG.log(Level.WARNING, "General vehicle search failed", ex);
            return ResponseEntity.status(resolveStatus(ex)).build();
        }
    }

    @PostMapping("/{vehicleId}/drivers")
    @Operation(summary = "Bind Driver")
    public ResponseEntity<DriverVehicle> bindDriver(@PathVariable Long vehicleId,
                                                    @RequestBody DriverVehicle relation,
                                                    @RequestHeader(value = "Idempotency-Key", required = false)
                                                    String idempotencyKey) {
        boolean useKey = hasKey(idempotencyKey);
        try {
            relation.setVehicleId(vehicleId);
            if (useKey) {
                if (driverVehicleService.shouldSkipProcessing(idempotencyKey)) {
                    return ResponseEntity.status(HttpStatus.ALREADY_REPORTED).build();
                }
                driverVehicleService.checkAndInsertIdempotency(idempotencyKey, relation, "create");
            }
            DriverVehicle saved = driverVehicleService.createBinding(relation);
            if (useKey && saved.getId() != null) {
                driverVehicleService.markHistorySuccess(idempotencyKey, saved.getId());
            }
            return ResponseEntity.status(HttpStatus.CREATED).body(saved);
        } catch (Exception ex) {
            if (useKey) {
                driverVehicleService.markHistoryFailure(idempotencyKey, ex.getMessage());
            }
            LOG.log(Level.SEVERE, "Create driver-vehicle binding failed", ex);
            return ResponseEntity.status(resolveStatus(ex)).build();
        }
    }

    @GetMapping("/{vehicleId}/drivers")
    @Operation(summary = "List Bindings")
    public ResponseEntity<List<DriverVehicle>> listBindings(@PathVariable Long vehicleId,
                                                            @RequestParam(defaultValue = "1") int page,
                                                            @RequestParam(defaultValue = "20") int size) {
        try {
            return ResponseEntity.ok(driverVehicleService.findByVehicleId(vehicleId, page, size));
        } catch (Exception ex) {
            LOG.log(Level.WARNING, "List driver-vehicle binding failed", ex);
            return ResponseEntity.status(resolveStatus(ex)).build();
        }
    }

    @DeleteMapping("/bindings/{bindingId}")
    @Operation(summary = "Delete Binding")
    public ResponseEntity<Void> deleteBinding(@PathVariable Long bindingId) {
        try {
            driverVehicleService.deleteBinding(bindingId);
            return ResponseEntity.noContent().build();
        } catch (Exception ex) {
            LOG.log(Level.WARNING, "Delete driver-vehicle binding failed", ex);
            return ResponseEntity.status(resolveStatus(ex)).build();
        }
    }

    @PutMapping("/bindings/{bindingId}")
    @Operation(summary = "Update Binding")
    public ResponseEntity<DriverVehicle> updateBinding(@PathVariable Long bindingId,
                                                       @RequestBody DriverVehicle relation,
                                                       @RequestHeader(value = "Idempotency-Key", required = false)
                                                       String idempotencyKey) {
        boolean useKey = hasKey(idempotencyKey);
        try {
            relation.setId(bindingId);
            if (useKey) {
                if (driverVehicleService.shouldSkipProcessing(idempotencyKey)) {
                    return ResponseEntity.status(HttpStatus.ALREADY_REPORTED).build();
                }
                driverVehicleService.checkAndInsertIdempotency(idempotencyKey, relation, "update");
            }
            DriverVehicle updated = driverVehicleService.updateBinding(relation);
            if (useKey && updated.getId() != null) {
                driverVehicleService.markHistorySuccess(idempotencyKey, updated.getId());
            }
            return ResponseEntity.ok(updated);
        } catch (Exception ex) {
            if (useKey) {
                driverVehicleService.markHistoryFailure(idempotencyKey, ex.getMessage());
            }
            LOG.log(Level.SEVERE, "Update driver-vehicle binding failed", ex);
            return ResponseEntity.status(resolveStatus(ex)).build();
        }
    }

    @GetMapping("/bindings/{bindingId}")
    @Operation(summary = "Get Binding")
    public ResponseEntity<DriverVehicle> getBinding(@PathVariable Long bindingId) {
        try {
            DriverVehicle binding = driverVehicleService.findById(bindingId);
            return binding == null ? ResponseEntity.notFound().build() : ResponseEntity.ok(binding);
        } catch (Exception ex) {
            LOG.log(Level.WARNING, "Get driver-vehicle binding failed", ex);
            return ResponseEntity.status(resolveStatus(ex)).build();
        }
    }

    @GetMapping("/bindings")
    @Operation(summary = "List Bindings Overview")
    public ResponseEntity<List<DriverVehicle>> listBindingsOverview(@RequestParam(defaultValue = "1") int page,
                                                                    @RequestParam(defaultValue = "20") int size) {
        try {
            return ResponseEntity.ok(driverVehicleService.findAll(page, size));
        } catch (Exception ex) {
            LOG.log(Level.WARNING, "List driver-vehicle bindings failed", ex);
            return ResponseEntity.status(resolveStatus(ex)).build();
        }
    }

    @GetMapping("/drivers/{driverId}/vehicles")
    @Operation(summary = "List By Driver")
    public ResponseEntity<List<DriverVehicle>> listByDriver(@PathVariable Long driverId,
                                                            @RequestParam(defaultValue = "1") int page,
                                                            @RequestParam(defaultValue = "20") int size) {
        try {
            return ResponseEntity.ok(driverVehicleService.findByDriverId(driverId, page, size));
        } catch (Exception ex) {
            LOG.log(Level.WARNING, "List driver bindings failed", ex);
            return ResponseEntity.status(resolveStatus(ex)).build();
        }
    }

    @GetMapping("/drivers/{driverId}/vehicles/primary")
    @Operation(summary = "Primary Binding")
    public ResponseEntity<List<DriverVehicle>> primaryBinding(@PathVariable Long driverId) {
        try {
            return ResponseEntity.ok(driverVehicleService.findPrimaryBinding(driverId));
        } catch (Exception ex) {
            LOG.log(Level.WARNING, "Get primary binding failed", ex);
            return ResponseEntity.status(resolveStatus(ex)).build();
        }
    }

    @GetMapping("/bindings/search/relationship")
    @Operation(summary = "Search By Relationship")
    public ResponseEntity<List<DriverVehicle>> searchByRelationship(@RequestParam String relationship,
                                                                    @RequestParam(defaultValue = "1") int page,
                                                                    @RequestParam(defaultValue = "20") int size) {
        try {
            return ResponseEntity.ok(driverVehicleService.searchByRelationship(relationship, page, size));
        } catch (Exception ex) {
            LOG.log(Level.WARNING, "Search bindings by relationship failed", ex);
            return ResponseEntity.status(resolveStatus(ex)).build();
        }
    }

    @GetMapping("/me/autocomplete/plates")
    @RolesAllowed({"SUPER_ADMIN", "ADMIN", "TRAFFIC_POLICE", "USER"})
    @Operation(summary = "Current User Plate Autocomplete")
    public ResponseEntity<List<String>> currentUserPlateAutocomplete(@RequestParam String prefix,
                                                                     @RequestParam(defaultValue = "10") int size) {
        try {
            return ResponseEntity.ok(currentUserTrafficSupportService.getCurrentUserVehiclePlateSuggestions(prefix, size));
        } catch (IllegalStateException ex) {
            return ResponseEntity.status(HttpStatus.FORBIDDEN).build();
        } catch (Exception ex) {
            LOG.log(Level.WARNING, "Fetch current user plate autocomplete failed", ex);
            return ResponseEntity.status(resolveStatus(ex)).build();
        }
    }

    @GetMapping("/me/autocomplete/types")
    @RolesAllowed({"SUPER_ADMIN", "ADMIN", "TRAFFIC_POLICE", "USER"})
    @Operation(summary = "Current User Vehicle Type Autocomplete")
    public ResponseEntity<List<String>> currentUserVehicleTypeAutocomplete(@RequestParam String prefix,
                                                                           @RequestParam(defaultValue = "10") int size) {
        try {
            return ResponseEntity.ok(currentUserTrafficSupportService.getCurrentUserVehicleTypeSuggestions(prefix, size));
        } catch (IllegalStateException ex) {
            return ResponseEntity.status(HttpStatus.FORBIDDEN).build();
        } catch (Exception ex) {
            LOG.log(Level.WARNING, "Fetch current user vehicle type autocomplete failed", ex);
            return ResponseEntity.status(resolveStatus(ex)).build();
        }
    }

    @GetMapping("/search/license/global")
    @Operation(summary = "Global Plate Suggestions")
    @RolesAllowed({"SUPER_ADMIN", "ADMIN", "TRAFFIC_POLICE", "FINANCE"})
    public ResponseEntity<List<String>> globalPlateSuggestions(@RequestParam String prefix,
                                                               @RequestParam(defaultValue = "10") int size) {
        try {
            return ResponseEntity.ok(vehicleInformationService.getVehicleInformationByLicensePlateGlobally(prefix, size));
        } catch (Exception ex) {
            LOG.log(Level.WARNING, "Fetch global plate suggestions failed", ex);
            return ResponseEntity.status(resolveStatus(ex)).build();
        }
    }

    @GetMapping("/autocomplete/plates")
    @Operation(summary = "Plate Autocomplete")
    public ResponseEntity<List<String>> plateAutocomplete(@RequestParam String prefix,
                                                          @RequestParam(defaultValue = "10") int size,
                                                          @RequestParam String idCard) {
        try {
            return ResponseEntity.ok(vehicleInformationService.getLicensePlateAutocompleteSuggestions(prefix, size, idCard));
        } catch (Exception ex) {
            LOG.log(Level.WARNING, "Fetch plate autocomplete failed", ex);
            return ResponseEntity.status(resolveStatus(ex)).build();
        }
    }

    @GetMapping("/autocomplete/types")
    @Operation(summary = "Vehicle Type Autocomplete")
    public ResponseEntity<List<String>> vehicleTypeAutocomplete(@RequestParam String idCard,
                                                                @RequestParam String prefix,
                                                                @RequestParam(defaultValue = "10") int size) {
        try {
            return ResponseEntity.ok(vehicleInformationService.getVehicleTypeAutocompleteSuggestions(idCard, prefix, size));
        } catch (Exception ex) {
            LOG.log(Level.WARNING, "Fetch vehicle type autocomplete failed", ex);
            return ResponseEntity.status(resolveStatus(ex)).build();
        }
    }

    @GetMapping("/autocomplete/types/global")
    @Operation(summary = "Vehicle Type Autocomplete Global")
    public ResponseEntity<List<String>> vehicleTypeAutocompleteGlobal(@RequestParam String prefix,
                                                                      @RequestParam(defaultValue = "10") int size) {
        try {
            return ResponseEntity.ok(vehicleInformationService.getVehicleTypesByPrefixGlobally(prefix, size));
        } catch (Exception ex) {
            LOG.log(Level.WARNING, "Fetch global vehicle type autocomplete failed", ex);
            return ResponseEntity.status(resolveStatus(ex)).build();
        }
    }

    @GetMapping("/exists/{licensePlate}")
    @RolesAllowed({"SUPER_ADMIN", "ADMIN", "TRAFFIC_POLICE", "USER"})
    @Operation(summary = "License Exists")
    public ResponseEntity<Map<String, Boolean>> licenseExists(@PathVariable String licensePlate) {
        try {
            boolean exists = vehicleInformationService.isLicensePlateExists(licensePlate);
            return ResponseEntity.ok(Map.of("exists", exists));
        } catch (Exception ex) {
            LOG.log(Level.WARNING, "License plate existence check failed", ex);
            return ResponseEntity.status(resolveStatus(ex)).build();
        }
    }

    private boolean hasKey(String value) {
        return value != null && !value.isBlank();
    }

    private HttpStatus resolveStatus(Exception ex) {
        return (ex instanceof IllegalArgumentException || ex instanceof IllegalStateException)
                ? HttpStatus.BAD_REQUEST
                : HttpStatus.INTERNAL_SERVER_ERROR;
    }
}
