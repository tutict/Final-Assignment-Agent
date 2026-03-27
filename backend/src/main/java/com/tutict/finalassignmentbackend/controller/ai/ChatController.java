package com.tutict.finalassignmentbackend.controller.ai;

import com.tutict.finalassignmentbackend.model.ai.AgentEvent;
import com.tutict.finalassignmentbackend.model.ai.AgentSkillInfo;
import com.tutict.finalassignmentbackend.model.ai.ChatActionResponse;
import com.tutict.finalassignmentbackend.service.ChatAgent;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.Parameter;
import io.swagger.v3.oas.annotations.responses.ApiResponse;
import io.swagger.v3.oas.annotations.responses.ApiResponses;
import io.swagger.v3.oas.annotations.tags.Tag;
import org.springframework.http.MediaType;
import org.springframework.http.codec.ServerSentEvent;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import reactor.core.publisher.Flux;

import java.util.List;

@RestController
@RequestMapping("/api/ai")
@Tag(name = "AI Chat", description = "交通违法业务 Agent 接口")
public class ChatController {

    private final ChatAgent chatAgent;

    public ChatController(ChatAgent chatAgent) {
        this.chatAgent = chatAgent;
    }

    @GetMapping(value = "/chat", produces = MediaType.TEXT_EVENT_STREAM_VALUE)
    @Operation(
            summary = "交通业务 Agent 流式对话",
            description = "通过 SSE 返回 Agent 的状态、联网检索结果、回答正文和动作建议。"
    )
    @ApiResponses({
            @ApiResponse(responseCode = "200", description = "成功返回流式响应"),
            @ApiResponse(responseCode = "400", description = "缺少 message/massage 参数"),
            @ApiResponse(responseCode = "500", description = "服务内部错误")
    })
    public Flux<ServerSentEvent<AgentEvent>> chat(
            @RequestParam(value = "message", required = false)
            @Parameter(description = "用户输入，推荐使用该参数", example = "如何处理超速罚单？")
            String message,
            @RequestParam(value = "massage", required = false)
            @Parameter(description = "兼容旧参数，已废弃", deprecated = true)
            String massage,
            @RequestParam(value = "webSearch", defaultValue = "false")
            @Parameter(description = "是否启用联网检索", example = "true")
            boolean webSearch) {
        return chatAgent.streamChat(message, massage, webSearch);
    }

    @GetMapping(value = "/chat/actions", produces = MediaType.APPLICATION_JSON_VALUE)
    @Operation(
            summary = "获取 Agent 动作方案",
            description = "返回可执行的页面动作建议，适合前端二次确认后执行。"
    )
    @ApiResponses({
            @ApiResponse(responseCode = "200", description = "成功返回动作方案"),
            @ApiResponse(responseCode = "400", description = "缺少 message/massage 参数"),
            @ApiResponse(responseCode = "500", description = "服务内部错误")
    })
    public ChatActionResponse chatActions(
            @RequestParam(value = "message", required = false)
            @Parameter(description = "用户输入，推荐使用该参数", example = "帮我打开罚款查询页面")
            String message,
            @RequestParam(value = "massage", required = false)
            @Parameter(description = "兼容旧参数，已废弃", deprecated = true)
            String massage,
            @RequestParam(value = "webSearch", defaultValue = "false")
            @Parameter(description = "是否启用联网检索", example = "true")
            boolean webSearch) {
        return chatAgent.chatWithActions(message, massage, webSearch);
    }

    @GetMapping(value = "/skills", produces = MediaType.APPLICATION_JSON_VALUE)
    @Operation(summary = "列出当前 Agent skills", description = "前端可据此展示 Agent 的能力清单。")
    public List<AgentSkillInfo> skills() {
        return chatAgent.listSkills();
    }
}
