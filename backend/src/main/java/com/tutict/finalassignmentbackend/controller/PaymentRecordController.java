package com.tutict.finalassignmentbackend.controller;

import com.tutict.finalassignmentbackend.config.statemachine.states.PaymentState;
import com.tutict.finalassignmentbackend.entity.PaymentRecord;
import com.tutict.finalassignmentbackend.service.CurrentUserTrafficSupportService;
import com.tutict.finalassignmentbackend.service.PaymentRecordService;
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
import java.util.logging.Level;
import java.util.logging.Logger;

@RestController
@RequestMapping("/api/payments")
@Tag(name = "", description = " endpoints")
@SecurityRequirement(name = "bearerAuth")
@RolesAllowed({"SUPER_ADMIN", "ADMIN", "FINANCE"})
public class PaymentRecordController {

    private static final Logger LOG = Logger.getLogger(PaymentRecordController.class.getName());

    private final PaymentRecordService paymentRecordService;
    private final CurrentUserTrafficSupportService currentUserTrafficSupportService;

    public PaymentRecordController(PaymentRecordService paymentRecordService,
                                   CurrentUserTrafficSupportService currentUserTrafficSupportService) {
        this.paymentRecordService = paymentRecordService;
        this.currentUserTrafficSupportService = currentUserTrafficSupportService;
    }

    @PostMapping("/me")
    @RolesAllowed({"SUPER_ADMIN", "ADMIN", "FINANCE", "USER"})
    @Operation(summary = "Create Current User Payment")
    public ResponseEntity<PaymentRecord> createCurrentUserPayment(@RequestBody PaymentRecord request,
                                                                  @RequestHeader(value = "Idempotency-Key", required = false)
                                                                  String idempotencyKey) {
        boolean useKey = hasKey(idempotencyKey);
        try {
            if (useKey) {
                if (paymentRecordService.shouldSkipProcessing(idempotencyKey)) {
                    return ResponseEntity.status(HttpStatus.ALREADY_REPORTED).build();
                }
                paymentRecordService.checkAndInsertIdempotency(idempotencyKey, request, "create");
            }
            PaymentRecord saved = currentUserTrafficSupportService.createPaymentForCurrentUser(request);
            if (useKey && saved.getPaymentId() != null) {
                paymentRecordService.markHistorySuccess(idempotencyKey, saved.getPaymentId());
            }
            return ResponseEntity.status(HttpStatus.CREATED).body(saved);
        } catch (Exception ex) {
            if (useKey) {
                paymentRecordService.markHistoryFailure(idempotencyKey, ex.getMessage());
            }
            LOG.log(Level.SEVERE, "Create current user payment failed", ex);
            return ResponseEntity.status(resolveStatus(ex)).build();
        }
    }

    @GetMapping("/me")
    @RolesAllowed({"USER"})
    @Operation(summary = "List Current User Payments")
    public ResponseEntity<List<PaymentRecord>> listCurrentUserPayments(@RequestParam(defaultValue = "1") int page,
                                                                       @RequestParam(defaultValue = "20") int size,
                                                                       @RequestParam(required = false) Long fineId) {
        try {
            return ResponseEntity.ok(fineId == null
                    ? currentUserTrafficSupportService.listCurrentUserPayments(page, size)
                    : currentUserTrafficSupportService.listCurrentUserPaymentsByFineId(fineId, page, size));
        } catch (Exception ex) {
            LOG.log(Level.WARNING, "List current user payments failed", ex);
            return ResponseEntity.status(resolveStatus(ex)).build();
        }
    }

    @PostMapping("/me/{paymentId}/confirm")
    @RolesAllowed({"USER"})
    @Operation(summary = "Confirm Current User Payment")
    public ResponseEntity<PaymentRecord> confirmCurrentUserPayment(@PathVariable Long paymentId,
                                                                   @RequestBody CurrentUserPaymentConfirmationRequest request,
                                                                   @RequestHeader(value = "Idempotency-Key", required = false)
                                                                   String idempotencyKey) {
        boolean useKey = hasKey(idempotencyKey);
        try {
            PaymentRecord confirmationDraft = new PaymentRecord();
            confirmationDraft.setPaymentId(paymentId);
            confirmationDraft.setTransactionId(request == null ? null : request.getTransactionId());
            confirmationDraft.setReceiptUrl(request == null ? null : request.getReceiptUrl());
            if (useKey) {
                if (paymentRecordService.shouldSkipProcessing(idempotencyKey)) {
                    return ResponseEntity.status(HttpStatus.ALREADY_REPORTED).build();
                }
                paymentRecordService.checkAndInsertIdempotency(idempotencyKey, confirmationDraft, "confirm");
            }
            PaymentRecord confirmed =
                    currentUserTrafficSupportService.confirmCurrentUserPayment(paymentId, confirmationDraft);
            if (useKey && confirmed.getPaymentId() != null) {
                paymentRecordService.markHistorySuccess(idempotencyKey, confirmed.getPaymentId());
            }
            return ResponseEntity.ok(confirmed);
        } catch (Exception ex) {
            if (useKey) {
                paymentRecordService.markHistoryFailure(idempotencyKey, ex.getMessage());
            }
            LOG.log(Level.WARNING, "Confirm current user payment failed", ex);
            return ResponseEntity.status(resolveStatus(ex)).build();
        }
    }

    @PostMapping("/me/{paymentId}/proof")
    @RolesAllowed({"USER"})
    @Operation(summary = "Update Current User Payment Proof")
    public ResponseEntity<PaymentRecord> updateCurrentUserPaymentProof(@PathVariable Long paymentId,
                                                                       @RequestBody CurrentUserPaymentProofRequest request,
                                                                       @RequestHeader(value = "Idempotency-Key", required = false)
                                                                       String idempotencyKey) {
        boolean useKey = hasKey(idempotencyKey);
        try {
            PaymentRecord proofDraft = new PaymentRecord();
            proofDraft.setPaymentId(paymentId);
            proofDraft.setReceiptUrl(request == null ? null : request.getReceiptUrl());
            if (useKey) {
                if (paymentRecordService.shouldSkipProcessing(idempotencyKey)) {
                    return ResponseEntity.status(HttpStatus.ALREADY_REPORTED).build();
                }
                paymentRecordService.checkAndInsertIdempotency(idempotencyKey, proofDraft, "proof");
            }
            PaymentRecord updated =
                    currentUserTrafficSupportService.updateCurrentUserPaymentProof(paymentId, proofDraft);
            if (useKey && updated.getPaymentId() != null) {
                paymentRecordService.markHistorySuccess(idempotencyKey, updated.getPaymentId());
            }
            return ResponseEntity.ok(updated);
        } catch (Exception ex) {
            if (useKey) {
                paymentRecordService.markHistoryFailure(idempotencyKey, ex.getMessage());
            }
            LOG.log(Level.WARNING, "Update current user payment proof failed", ex);
            return ResponseEntity.status(resolveStatus(ex)).build();
        }
    }

    @PostMapping("/{paymentId}/finance-review")
    @Operation(summary = "Review Self-Service Payment")
    public ResponseEntity<PaymentRecord> reviewPayment(@PathVariable Long paymentId,
                                                       @RequestBody PaymentFinanceReviewRequest request,
                                                       @RequestHeader(value = "Idempotency-Key", required = false)
                                                       String idempotencyKey) {
        boolean useKey = hasKey(idempotencyKey);
        try {
            PaymentRecord reviewDraft = new PaymentRecord();
            reviewDraft.setPaymentId(paymentId);
            if (request != null) {
                reviewDraft.setRemarks("reviewResult=" + request.getReviewResult()
                        + ",reviewOpinion=" + request.getReviewOpinion());
            }
            if (useKey) {
                if (paymentRecordService.shouldSkipProcessing(idempotencyKey)) {
                    return ResponseEntity.status(HttpStatus.ALREADY_REPORTED).build();
                }
                paymentRecordService.checkAndInsertIdempotency(idempotencyKey, reviewDraft, "review");
            }
            PaymentRecord reviewed = paymentRecordService.recordFinanceReview(
                    paymentId,
                    request == null ? null : request.getReviewResult(),
                    request == null ? null : request.getReviewOpinion());
            if (useKey && reviewed.getPaymentId() != null) {
                paymentRecordService.markHistorySuccess(idempotencyKey, reviewed.getPaymentId());
            }
            return ResponseEntity.ok(reviewed);
        } catch (Exception ex) {
            if (useKey) {
                paymentRecordService.markHistoryFailure(idempotencyKey, ex.getMessage());
            }
            LOG.log(Level.WARNING, "Review payment failed", ex);
            return ResponseEntity.status(resolveStatus(ex)).build();
        }
    }

    @PostMapping
    @Operation(summary = "Create Payment")
    public ResponseEntity<PaymentRecord> createPayment(@RequestBody PaymentRecord request,
                                                       @RequestHeader(value = "Idempotency-Key", required = false)
                                                       String idempotencyKey) {
        boolean useKey = hasKey(idempotencyKey);
        try {
            if (useKey) {
                if (paymentRecordService.shouldSkipProcessing(idempotencyKey)) {
                    return ResponseEntity.status(HttpStatus.ALREADY_REPORTED).build();
                }
                paymentRecordService.checkAndInsertIdempotency(idempotencyKey, request, "create");
            }
            PaymentRecord saved = paymentRecordService.createPaymentRecord(request);
            if (useKey && saved.getPaymentId() != null) {
                paymentRecordService.markHistorySuccess(idempotencyKey, saved.getPaymentId());
            }
            return ResponseEntity.status(HttpStatus.CREATED).body(saved);
        } catch (Exception ex) {
            if (useKey) {
                paymentRecordService.markHistoryFailure(idempotencyKey, ex.getMessage());
            }
            LOG.log(Level.SEVERE, "Create payment record failed", ex);
            return ResponseEntity.status(resolveStatus(ex)).build();
        }
    }

    @PutMapping("/{paymentId}")
    @Operation(summary = "Update Payment")
    public ResponseEntity<PaymentRecord> updatePayment(@PathVariable Long paymentId,
                                                       @RequestBody PaymentRecord request,
                                                       @RequestHeader(value = "Idempotency-Key", required = false)
                                                       String idempotencyKey) {
        return ResponseEntity.status(HttpStatus.METHOD_NOT_ALLOWED).build();
    }

    @DeleteMapping("/{paymentId}")
    @Operation(summary = "Delete Payment")
    public ResponseEntity<Void> deletePayment(@PathVariable Long paymentId) {
        return ResponseEntity.status(HttpStatus.METHOD_NOT_ALLOWED).build();
    }

    @GetMapping("/{paymentId}")
    @Operation(summary = "Get Payment")
    public ResponseEntity<PaymentRecord> getPayment(@PathVariable Long paymentId) {
        PaymentRecord record = paymentRecordService.findById(paymentId);
        return record == null ? ResponseEntity.notFound().build() : ResponseEntity.ok(record);
    }

    @GetMapping
    @Operation(summary = "List Payments")
    public ResponseEntity<List<PaymentRecord>> listPayments(@RequestParam(defaultValue = "1") int page,
                                                            @RequestParam(defaultValue = "20") int size) {
        return ResponseEntity.ok(paymentRecordService.listPayments(page, size));
    }

    @GetMapping("/fine/{fineId}")
    @Operation(summary = "Find By Fine")
    public ResponseEntity<List<PaymentRecord>> findByFine(@PathVariable Long fineId,
                                                          @RequestParam(defaultValue = "1") int page,
                                                          @RequestParam(defaultValue = "20") int size) {
        return ResponseEntity.ok(paymentRecordService.findByFineId(fineId, page, size));
    }

    @GetMapping("/search/payer")
    @Operation(summary = "Search By Payer")
    public ResponseEntity<List<PaymentRecord>> searchByPayer(@RequestParam("idCard") String idCard,
                                                             @RequestParam(defaultValue = "1") int page,
                                                             @RequestParam(defaultValue = "20") int size) {
        return ResponseEntity.ok(paymentRecordService.searchByPayerIdCard(idCard, page, size));
    }

    @GetMapping("/search/status")
    @Operation(summary = "Search By Status")
    public ResponseEntity<List<PaymentRecord>> searchByStatus(@RequestParam String status,
                                                              @RequestParam(defaultValue = "1") int page,
                                                              @RequestParam(defaultValue = "20") int size) {
        return ResponseEntity.ok(paymentRecordService.searchByPaymentStatus(status, page, size));
    }

    @GetMapping("/search/transaction")
    @Operation(summary = "Search By Transaction")
    public ResponseEntity<List<PaymentRecord>> searchByTransaction(@RequestParam String transactionId,
                                                                   @RequestParam(defaultValue = "1") int page,
                                                                   @RequestParam(defaultValue = "20") int size) {
        return ResponseEntity.ok(paymentRecordService.searchByTransactionId(transactionId, page, size));
    }

    @GetMapping("/search/payment-number")
    @Operation(summary = "Search By Payment Number")
    public ResponseEntity<List<PaymentRecord>> searchByPaymentNumber(@RequestParam String paymentNumber,
                                                                     @RequestParam(defaultValue = "1") int page,
                                                                     @RequestParam(defaultValue = "20") int size) {
        return ResponseEntity.ok(paymentRecordService.searchByPaymentNumber(paymentNumber, page, size));
    }

    @GetMapping("/search/payer-name")
    @Operation(summary = "Search By Payer Name")
    public ResponseEntity<List<PaymentRecord>> searchByPayerName(@RequestParam String payerName,
                                                                 @RequestParam(defaultValue = "1") int page,
                                                                 @RequestParam(defaultValue = "20") int size) {
        return ResponseEntity.ok(paymentRecordService.searchByPayerName(payerName, page, size));
    }

    @GetMapping("/search/payment-method")
    @Operation(summary = "Search By Payment Method")
    public ResponseEntity<List<PaymentRecord>> searchByPaymentMethod(@RequestParam String paymentMethod,
                                                                     @RequestParam(defaultValue = "1") int page,
                                                                     @RequestParam(defaultValue = "20") int size) {
        return ResponseEntity.ok(paymentRecordService.searchByPaymentMethod(paymentMethod, page, size));
    }

    @GetMapping("/search/payment-channel")
    @Operation(summary = "Search By Payment Channel")
    public ResponseEntity<List<PaymentRecord>> searchByPaymentChannel(@RequestParam String paymentChannel,
                                                                      @RequestParam(defaultValue = "1") int page,
                                                                      @RequestParam(defaultValue = "20") int size) {
        return ResponseEntity.ok(paymentRecordService.searchByPaymentChannel(paymentChannel, page, size));
    }

    @GetMapping("/review-tasks")
    @Operation(summary = "List Finance Review Tasks")
    public ResponseEntity<List<PaymentRecord>> listFinanceReviewTasks(@RequestParam(defaultValue = "1") int page,
                                                                      @RequestParam(defaultValue = "20") int size) {
        return ResponseEntity.ok(paymentRecordService.listFinanceReviewTasks(page, size));
    }

    @GetMapping("/search/time-range")
    @Operation(summary = "Search By Time Range")
    public ResponseEntity<List<PaymentRecord>> searchByTimeRange(@RequestParam String startTime,
                                                                 @RequestParam String endTime,
                                                                 @RequestParam(defaultValue = "1") int page,
                                                                 @RequestParam(defaultValue = "20") int size) {
        return ResponseEntity.ok(paymentRecordService.searchByPaymentTimeRange(startTime, endTime, page, size));
    }

    @PutMapping("/{paymentId}/status/{state}")
    @Operation(summary = "Update Payment Status")
    public ResponseEntity<PaymentRecord> updatePaymentStatus(@PathVariable Long paymentId,
                                                             @PathVariable PaymentState state) {
        try {
            PaymentRecord updated = paymentRecordService.transitionPaymentStatus(paymentId, state);
            return ResponseEntity.ok(updated);
        } catch (Exception ex) {
            LOG.log(Level.WARNING, "Update payment status failed", ex);
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

    public static class CurrentUserPaymentConfirmationRequest {
        private String transactionId;
        private String receiptUrl;

        public String getTransactionId() {
            return transactionId;
        }

        public void setTransactionId(String transactionId) {
            this.transactionId = transactionId;
        }

        public String getReceiptUrl() {
            return receiptUrl;
        }

        public void setReceiptUrl(String receiptUrl) {
            this.receiptUrl = receiptUrl;
        }
    }

    public static class PaymentFinanceReviewRequest {
        private String reviewResult;
        private String reviewOpinion;

        public String getReviewResult() {
            return reviewResult;
        }

        public void setReviewResult(String reviewResult) {
            this.reviewResult = reviewResult;
        }

        public String getReviewOpinion() {
            return reviewOpinion;
        }

        public void setReviewOpinion(String reviewOpinion) {
            this.reviewOpinion = reviewOpinion;
        }
    }

    public static class CurrentUserPaymentProofRequest {
        private String receiptUrl;

        public String getReceiptUrl() {
            return receiptUrl;
        }

        public void setReceiptUrl(String receiptUrl) {
            this.receiptUrl = receiptUrl;
        }
    }
}
