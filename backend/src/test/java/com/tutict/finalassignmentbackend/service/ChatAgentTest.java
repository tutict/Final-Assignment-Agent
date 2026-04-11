package com.tutict.finalassignmentbackend.service;

import com.tutict.finalassignmentbackend.model.ai.AgentEvent;
import com.tutict.finalassignmentbackend.service.agent.AgentSkill;
import com.tutict.finalassignmentbackend.service.agent.AgentSkillContext;
import com.tutict.finalassignmentbackend.service.agent.AgentSkillResult;
import com.tutict.finalassignmentbackend.service.agent.AgentUserContextResolver;
import org.junit.jupiter.api.Test;
import org.mockito.Mockito;

import java.time.Duration;
import java.util.List;

import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoMoreInteractions;
import static org.mockito.Mockito.when;

class ChatAgentTest {

    @Test
    void shouldCaptureResolvedContextBeforeAsyncStreaming() {
        AgentUserContextResolver resolver = Mockito.mock(AgentUserContextResolver.class);
        AgentSkillContext context = new AgentSkillContext(
                "查询我的违法记录",
                false,
                true,
                "user01",
                1L,
                "Test User",
                "330123199001010011",
                "群众",
                List.of()
        );
        when(resolver.resolve("查询我的违法记录", false)).thenReturn(context);

        AgentSkill skill = new AgentSkill() {
            @Override
            public String id() {
                return "test-skill";
            }

            @Override
            public String displayName() {
                return "Test Skill";
            }

            @Override
            public String description() {
                return "Test";
            }

            @Override
            public AgentSkillResult execute(AgentSkillContext skillContext) {
                return new AgentSkillResult(
                        id(),
                        "captured-user=" + skillContext.username(),
                        List.of("先核对违法时间与地点"),
                        List.of(),
                        List.of(),
                        false
                );
            }
        };

        ChatAgent chatAgent = new ChatAgent(List.of(skill), resolver);

        var flux = chatAgent.streamChatEvents("查询我的违法记录", null, false);
        verify(resolver).resolve("查询我的违法记录", false);

        List<AgentEvent> events = flux.collectList().block(Duration.ofSeconds(5));
        verifyNoMoreInteractions(resolver);

        AgentEvent contextEvent = events.stream()
                .filter(event -> "context".equals(event.type()))
                .findFirst()
                .orElse(null);
        assertNotNull(contextEvent);
        assertNotNull(contextEvent.agentContext());
        assertTrue(contextEvent.agentContext().operatorLabel().contains("Test User(user01)"));
        assertTrue(contextEvent.agentContext().accessScopeLabel().contains("本人名下"));

        AgentEvent firstStatus = events.stream()
                .filter(event -> "status".equals(event.type()))
                .findFirst()
                .orElse(null);
        assertNotNull(firstStatus);
        assertTrue(firstStatus.content().contains("正在分析问题并规划技能执行"));

        String combinedMessages = events.stream()
                .filter(event -> "message".equals(event.type()))
                .map(AgentEvent::content)
                .reduce("", String::concat);

        assertTrue(combinedMessages.contains("核心判断"));
        assertTrue(combinedMessages.contains("建议步骤"));
        assertTrue(combinedMessages.contains("captured-user=user01"));
        assertTrue(combinedMessages.contains("先核对违法时间与地点"));
    }
}
