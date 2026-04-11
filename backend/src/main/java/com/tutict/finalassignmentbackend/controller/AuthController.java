package com.tutict.finalassignmentbackend.controller;

import com.tutict.finalassignmentbackend.entity.SysUser;
import com.tutict.finalassignmentbackend.service.AuthWsService;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.Parameter;
import io.swagger.v3.oas.annotations.media.Content;
import io.swagger.v3.oas.annotations.media.Schema;
import io.swagger.v3.oas.annotations.responses.ApiResponse;
import io.swagger.v3.oas.annotations.responses.ApiResponses;
import io.swagger.v3.oas.annotations.security.SecurityRequirement;
import io.swagger.v3.oas.annotations.tags.Tag;
import jakarta.annotation.security.PermitAll;
import jakarta.annotation.security.RolesAllowed;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.scheduling.annotation.Async;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.List;
import java.util.Map;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.logging.Level;
import java.util.logging.Logger;

@RestController
@RequestMapping("/api/auth")
@Tag(name = "Authentication", description = "Authentication and registration endpoints")
public class AuthController {

    private static final Logger LOG = Logger.getLogger(AuthController.class.getName());
    private static final ExecutorService VIRTUAL_THREAD_EXECUTOR = Executors.newVirtualThreadPerTaskExecutor();

    private final AuthWsService authWsService;

    public AuthController(AuthWsService authWsService) {
        this.authWsService = authWsService;
    }

    @PostMapping("/login")
    @PermitAll
    @Async
    @Operation(
            summary = "User login",
            description = "Authenticates a user with username and password and returns a JWT payload."
    )
    @ApiResponses({
            @ApiResponse(
                    responseCode = "200",
                    description = "Login succeeded and returned a structured token payload.",
                    content = @Content(mediaType = "application/json",
                            schema = @Schema(type = "object",
                                    example = "{\"jwtToken\":\"<token>\",\"username\":\"admin\",\"roles\":[\"ROLE_ADMIN\"]}")))
            ,
            @ApiResponse(
                    responseCode = "400",
                    description = "Request parameters are missing or invalid.",
                    content = @Content(mediaType = "application/json",
                            schema = @Schema(type = "object", example = "{\"error\":\"Username and password are required\"}")))
            ,
            @ApiResponse(
                    responseCode = "401",
                    description = "Username or password is incorrect.",
                    content = @Content(mediaType = "application/json",
                            schema = @Schema(type = "object", example = "{\"error\":\"Invalid credentials\"}")))
    })
    public CompletableFuture<ResponseEntity<Map<String, Object>>> login(
            @RequestBody
            @Parameter(description = "Login request payload containing username and password", required = true)
            AuthWsService.LoginRequest loginRequest) {
        if (loginRequest == null || loginRequest.getUsername() == null || loginRequest.getPassword() == null) {
            LOG.log(Level.WARNING, "Login request missing username or password");
            return CompletableFuture.completedFuture(
                    ResponseEntity.status(HttpStatus.BAD_REQUEST)
                            .body(Map.of("error", "Username and password are required")));
        }

        return CompletableFuture.supplyAsync(() -> {
            try {
                Map<String, Object> result = authWsService.login(loginRequest);
                LOG.log(Level.INFO, "Login succeeded for username: {0}", loginRequest.getUsername());
                return ResponseEntity.ok(result);
            } catch (Exception ex) {
                LOG.log(Level.SEVERE, "Login failed for username: {0}, error: {1}",
                        new Object[]{loginRequest.getUsername(), ex.getMessage()});
                return ResponseEntity.status(HttpStatus.UNAUTHORIZED)
                        .body(Map.of("error", ex.getMessage()));
            }
        }, VIRTUAL_THREAD_EXECUTOR);
    }

    @PostMapping("/refresh")
    @PermitAll
    @Operation(summary = "Refresh access token")
    public ResponseEntity<Map<String, Object>> refreshToken(
            @RequestBody AuthWsService.RefreshRequest refreshRequest) {
        if (refreshRequest == null || refreshRequest.getRefreshToken() == null || refreshRequest.getRefreshToken().isBlank()) {
            return ResponseEntity.status(HttpStatus.BAD_REQUEST)
                    .body(Map.of("error", "Refresh token is required"));
        }
        try {
            return ResponseEntity.ok(authWsService.refreshToken(refreshRequest.getRefreshToken()));
        } catch (Exception ex) {
            LOG.log(Level.WARNING, "Refresh token failed: {0}", ex.getMessage());
            return ResponseEntity.status(HttpStatus.UNAUTHORIZED)
                    .body(Map.of("error", ex.getMessage()));
        }
    }

    @PostMapping("/register")
    @PermitAll
    @Async
    @Transactional
    @Operation(
            summary = "User registration",
            description = "Registers a new user, assigns the default role, and supports idempotent requests."
    )
    @ApiResponses({
            @ApiResponse(
                    responseCode = "201",
                    description = "Registration succeeded.",
                    content = @Content(mediaType = "application/json",
                            schema = @Schema(type = "object", example = "{\"status\":\"CREATED\"}")))
            ,
            @ApiResponse(
                    responseCode = "409",
                    description = "Username already exists or the request is duplicated.",
                    content = @Content(mediaType = "application/json",
                            schema = @Schema(type = "object", example = "{\"error\":\"Username already exists\"}")))
            ,
            @ApiResponse(
                    responseCode = "500",
                    description = "Internal server error.",
                    content = @Content(mediaType = "application/json",
                            schema = @Schema(type = "object", example = "{\"error\":\"Internal server error\"}")))
    })
    public CompletableFuture<ResponseEntity<Map<String, String>>> registerUser(
            @RequestBody
            @Parameter(description = "Registration request payload containing username, password, role, and idempotency key",
                    required = true)
            AuthWsService.RegisterRequest registerRequest) {
        return CompletableFuture.supplyAsync(() -> {
                    try {
                        String status = authWsService.registerUser(registerRequest);
                        LOG.log(Level.INFO, "Register succeeded for username: {0}", registerRequest.getUsername());
                        return ResponseEntity.status(HttpStatus.CREATED)
                                .body(Map.of("status", status));
                    } catch (Exception ex) {
                        LOG.log(Level.WARNING, "Register failed for username: {0}, error: {1}",
                                new Object[]{registerRequest.getUsername(), ex.getMessage()});
                        return ResponseEntity.status(HttpStatus.CONFLICT)
                                .body(Map.of("error", ex.getMessage()));
                    }
                }, VIRTUAL_THREAD_EXECUTOR)
                .exceptionally(throwable -> {
                    LOG.log(Level.SEVERE, "Unexpected error in registerUser for username: {0}, error: {1}",
                            new Object[]{registerRequest.getUsername(), throwable.getMessage()});
                    return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR)
                            .body(Map.of("error", "Internal server error"));
                });
    }

    @GetMapping("/users")
    @RolesAllowed({"SUPER_ADMIN", "ADMIN"})
    @SecurityRequirement(name = "bearerAuth")
    @Operation(
            summary = "List all users",
            description = "Returns all system users. Restricted to administrator roles."
    )
    @ApiResponses({
            @ApiResponse(
                    responseCode = "200",
                    description = "Query succeeded.",
                    content = @Content(mediaType = "application/json",
                            schema = @Schema(implementation = SysUser.class)))
            ,
            @ApiResponse(
                    responseCode = "403",
                    description = "Access denied.",
                    content = @Content(mediaType = "application/json",
                            schema = @Schema(type = "object", example = "{\"error\":\"Access denied\"}")))
    })
    public ResponseEntity<List<SysUser>> getAllUsers() {
        try {
            List<SysUser> users = authWsService.getAllUsers();
            LOG.log(Level.INFO, "Fetched {0} users", users.size());
            return ResponseEntity.ok(users);
        } catch (Exception ex) {
            LOG.log(Level.SEVERE, "GetAllUsers failed: {0}", ex.getMessage());
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR).body(List.of());
        }
    }
}
