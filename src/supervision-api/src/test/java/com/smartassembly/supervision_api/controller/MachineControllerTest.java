package com.smartassembly.supervision_api.controller;

import com.smartassembly.supervision_api.model.MachineState;
import com.smartassembly.supervision_api.service.MachineService;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.test.web.servlet.MockMvc;

import java.util.List;
import java.util.Optional;

import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.*;

/**
 * Tests unitaires du MachineController.
 *
 * Stratégie : @WebMvcTest charge uniquement la couche Web (Servlet + Jackson).
 * Le MachineService est mocké via @MockitoBean — aucun appel DynamoDB réel.
 *
 * Cas couverts :
 *   - GET /api/machines        → 200 liste / 200 liste vide
 *   - GET /api/machines/{id}   → 200 trouvé / 404 introuvable
 *   - GET /api/alerts          → 200 sans alerte / 200 avec alertes
 */
@org.springframework.boot.webmvc.test.autoconfigure.WebMvcTest(MachineController.class)
class MachineControllerTest {

    @Autowired
    private MockMvc mockMvc;

    @MockitoBean
    private MachineService machineService;

    // ── Helper ────────────────────────────────────────────────

    private MachineState buildMachine(String idPoste, String statut, String anomalieType) {
        MachineState m = new MachineState();
        m.setIdPoste(idPoste);
        m.setStatut(statut);
        m.setAnomalieType(anomalieType);
        m.setVibrationLast("3.5");
        m.setTemperatureLast("75.0");
        m.setPressionLast("4.5");
        return m;
    }

    // ── GET /api/machines ─────────────────────────────────────

    @Test
    void getAllMachines_shouldReturn200WithList() throws Exception {
        // Arrange
        when(machineService.getAllMachines()).thenReturn(List.of(
                buildMachine("poste_1", "EN_INTERVENTION", "VIBRATION"),
                buildMachine("poste_2", "OK", null)
        ));

        // Act + Assert
        mockMvc.perform(get("/api/machines"))
                .andExpect(status().isOk())
                .andExpect(content().contentTypeCompatibleWith("application/json"))
                .andExpect(jsonPath("$.length()").value(2))
                .andExpect(jsonPath("$[0].idPoste").value("poste_1"))
                .andExpect(jsonPath("$[0].statut").value("EN_INTERVENTION"))
                .andExpect(jsonPath("$[1].idPoste").value("poste_2"))
                .andExpect(jsonPath("$[1].statut").value("OK"));
    }

    @Test
    void getAllMachines_emptyTable_shouldReturn200WithEmptyArray() throws Exception {
        // Arrange
        when(machineService.getAllMachines()).thenReturn(List.of());

        // Act + Assert
        mockMvc.perform(get("/api/machines"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.length()").value(0));
    }

    // ── GET /api/machines/{idPoste} ───────────────────────────

    @Test
    void getMachine_existingId_shouldReturn200WithMachine() throws Exception {
        // Arrange
        MachineState machine = buildMachine("poste_1", "EN_INTERVENTION", "VIBRATION");
        when(machineService.getMachineById("poste_1")).thenReturn(Optional.of(machine));

        // Act + Assert
        mockMvc.perform(get("/api/machines/poste_1"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.idPoste").value("poste_1"))
                .andExpect(jsonPath("$.statut").value("EN_INTERVENTION"))
                .andExpect(jsonPath("$.anomalieType").value("VIBRATION"))
                .andExpect(jsonPath("$.vibrationLast").value("3.5"));
    }

    @Test
    void getMachine_unknownId_shouldReturn404() throws Exception {
        // Arrange
        when(machineService.getMachineById("poste_inconnu")).thenReturn(Optional.empty());

        // Act + Assert
        mockMvc.perform(get("/api/machines/poste_inconnu"))
                .andExpect(status().isNotFound());
    }

    // ── GET /api/alerts ───────────────────────────────────────

    @Test
    void getAlerts_noAlerts_shouldReturnCountZeroAndEmptyList() throws Exception {
        // Arrange
        when(machineService.getAlerts()).thenReturn(List.of());

        // Act + Assert
        mockMvc.perform(get("/api/alerts"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.count").value(0))
                .andExpect(jsonPath("$.alerts.length()").value(0));
    }

    @Test
    void getAlerts_withWarnAndCritical_shouldReturnCorrectCountAndList() throws Exception {
        // Arrange
        when(machineService.getAlerts()).thenReturn(List.of(
                buildMachine("poste_1", "WARN",     "TEMPERATURE"),
                buildMachine("poste_3", "CRITICAL",  "VIBRATION")
        ));

        // Act + Assert
        mockMvc.perform(get("/api/alerts"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.count").value(2))
                .andExpect(jsonPath("$.alerts.length()").value(2))
                .andExpect(jsonPath("$.alerts[0].statut").value("WARN"))
                .andExpect(jsonPath("$.alerts[1].statut").value("CRITICAL"));
    }
}
