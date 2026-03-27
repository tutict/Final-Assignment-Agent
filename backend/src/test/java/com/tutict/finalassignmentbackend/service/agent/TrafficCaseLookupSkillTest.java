package com.tutict.finalassignmentbackend.service.agent;

import com.tutict.finalassignmentbackend.entity.AppealRecord;
import com.tutict.finalassignmentbackend.entity.FineRecord;
import com.tutict.finalassignmentbackend.entity.OffenseRecord;
import com.tutict.finalassignmentbackend.entity.VehicleInformation;
import com.tutict.finalassignmentbackend.mapper.AppealRecordMapper;
import com.tutict.finalassignmentbackend.mapper.DriverInformationMapper;
import com.tutict.finalassignmentbackend.mapper.DriverVehicleMapper;
import com.tutict.finalassignmentbackend.mapper.FineRecordMapper;
import com.tutict.finalassignmentbackend.mapper.OffenseRecordMapper;
import com.tutict.finalassignmentbackend.mapper.VehicleInformationMapper;
import com.tutict.finalassignmentbackend.service.AppealRecordService;
import com.tutict.finalassignmentbackend.service.FineRecordService;
import com.tutict.finalassignmentbackend.service.OffenseRecordService;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.mockito.junit.jupiter.MockitoSettings;
import org.mockito.quality.Strictness;

import java.math.BigDecimal;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.util.List;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.when;

@ExtendWith(MockitoExtension.class)
@MockitoSettings(strictness = Strictness.LENIENT)
class TrafficCaseLookupSkillTest {

    @Mock
    private OffenseRecordService offenseRecordService;
    @Mock
    private FineRecordService fineRecordService;
    @Mock
    private AppealRecordService appealRecordService;
    @Mock
    private OffenseRecordMapper offenseRecordMapper;
    @Mock
    private FineRecordMapper fineRecordMapper;
    @Mock
    private AppealRecordMapper appealRecordMapper;
    @Mock
    private VehicleInformationMapper vehicleInformationMapper;
    @Mock
    private DriverInformationMapper driverInformationMapper;
    @Mock
    private DriverVehicleMapper driverVehicleMapper;

    @InjectMocks
    private TrafficCaseLookupSkill skill;

    @BeforeEach
    void setUp() {
        when(vehicleInformationMapper.selectList(any())).thenReturn(List.of());
        when(driverInformationMapper.selectList(any())).thenReturn(List.of());
        when(driverVehicleMapper.selectList(any())).thenReturn(List.of());
    }

    @Test
    void shouldLookupOwnedOffenseByNumber() {
        OffenseRecord record = new OffenseRecord();
        record.setOffenseId(11L);
        record.setOffenseNumber("OF-2026-001");
        record.setVehicleId(101L);
        record.setProcessStatus("Unprocessed");
        record.setOffenseTime(LocalDateTime.of(2026, 3, 27, 10, 30));
        record.setOffenseLocation("Hangzhou West Lake");
        record.setFineAmount(new BigDecimal("200"));

        VehicleInformation vehicle = new VehicleInformation();
        vehicle.setVehicleId(101L);
        vehicle.setLicensePlate("浙A12345");

        when(vehicleInformationMapper.selectList(any())).thenReturn(List.of(vehicle));
        when(offenseRecordMapper.selectList(any())).thenReturn(List.of(record));

        AgentSkillResult result = skill.execute(userContext("帮我查询违法编号 OF-2026-001 的状态"));

        assertTrue(result.summary().contains("违法编号"));
        assertEquals("/userOffenseListPage", result.actions().getFirst().getTarget());
        assertTrue(result.highlights().stream().anyMatch(item -> item.contains("OF-2026-001")));
        assertTrue(result.highlights().stream().anyMatch(item -> item.contains("当前身份")));
    }

    @Test
    void shouldLookupOwnedOffenseByLicensePlate() {
        OffenseRecord record = new OffenseRecord();
        record.setOffenseId(12L);
        record.setOffenseNumber("OF-2026-002");
        record.setVehicleId(101L);
        record.setProcessStatus("Processing");
        record.setOffenseLocation("Binjiang");

        VehicleInformation vehicle = new VehicleInformation();
        vehicle.setVehicleId(101L);
        vehicle.setLicensePlate("浙A12345");

        when(vehicleInformationMapper.selectList(any())).thenReturn(List.of(vehicle));
        when(vehicleInformationMapper.selectOne(any())).thenReturn(vehicle);
        when(offenseRecordService.findByVehicleId(eq(101L), eq(1), eq(3))).thenReturn(List.of(record));

        AgentSkillResult result = skill.execute(userContext("查询车牌号 浙A12345 的违法记录"));

        assertTrue(result.summary().contains("车牌号"));
        assertEquals("/userOffenseListPage", result.actions().getFirst().getTarget());
    }

    @Test
    void shouldRejectGlobalFineStatusForNormalUserWithVisibleRestrictionReason() {
        VehicleInformation vehicle = new VehicleInformation();
        vehicle.setVehicleId(101L);
        when(vehicleInformationMapper.selectList(any())).thenReturn(List.of(vehicle));

        AgentSkillResult result = skill.execute(userContext("查询未支付罚款记录"));

        assertTrue(result.summary().contains("不能直接按全局状态枚举案件"));
        assertEquals("/fineInformation", result.actions().getFirst().getTarget());
        assertTrue(result.highlights().stream().anyMatch(item -> item.contains("当前身份")));
        assertTrue(result.highlights().stream().anyMatch(item -> item.contains("访问范围")));
    }

    @Test
    void shouldAllowAdminFineStatusSearch() {
        FineRecord record = new FineRecord();
        record.setFineNumber("FN-88");
        record.setPaymentStatus("Unpaid");
        record.setTotalAmount(new BigDecimal("350"));
        record.setPaymentDeadline(LocalDate.of(2026, 4, 1));
        record.setHandler("Officer Lee");

        when(fineRecordService.searchByPaymentStatus(eq("Unpaid"), eq(1), eq(3))).thenReturn(List.of(record));

        AgentSkillResult result = skill.execute(adminContext("查询未支付罚款记录"));

        assertTrue(result.summary().contains("缴费状态"));
        assertEquals("/fineList", result.actions().getFirst().getTarget());
        assertTrue(result.highlights().stream().anyMatch(item -> item.contains("管理权限")));
        assertTrue(result.highlights().stream().anyMatch(item -> item.contains("FN-88")));
    }

    @Test
    void shouldRouteUserAppealLookupToUserAppealPage() {
        AppealRecord record = new AppealRecord();
        record.setAppealNumber("AP-3001");
        record.setAppellantIdCard("330123199001010011");
        record.setAcceptanceStatus("Accepted");
        record.setProcessStatus("Under_Review");
        record.setAppealTime(LocalDateTime.of(2026, 3, 25, 8, 0));
        record.setAppellantName("Zhang San");

        when(appealRecordMapper.selectList(any())).thenReturn(List.of(record));

        AgentSkillResult result = skill.execute(userContext("查询申诉编号 AP-3001"));

        assertEquals("/userAppeal", result.actions().getFirst().getTarget());
        assertTrue(result.highlights().stream().anyMatch(item -> item.contains("AP-3001")));
    }

    private AgentSkillContext userContext(String message) {
        return new AgentSkillContext(
                message,
                false,
                true,
                "user01",
                1L,
                "Test User",
                "330123199001010011",
                "群众",
                List.of()
        );
    }

    private AgentSkillContext adminContext(String message) {
        return new AgentSkillContext(
                message,
                false,
                true,
                "admin",
                99L,
                "Admin",
                "330123199001010099",
                "交警队",
                List.of("ROLE_ADMIN")
        );
    }
}
