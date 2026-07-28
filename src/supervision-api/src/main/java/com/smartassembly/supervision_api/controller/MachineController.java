package com.smartassembly.supervision_api.controller;


import com.smartassembly.supervision_api.model.MachineState;
import com.smartassembly.supervision_api.service.MachineService;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.util.List;
import java.util.Map;

/**
 * REST Controller — API de supervision des postes de travail.
 *
 * Endpoints :
 *   GET /api/machines          → tous les postes
 *   GET /api/machines/{id}     → un poste par id
 *   GET /api/alerts            → postes en WARN ou CRITICAL
 */
@RestController
@RequestMapping("/api")
public class MachineController {

    private final MachineService machineService;

    public MachineController(MachineService machineService) {
        this.machineService = machineService;
    }

    /**
     * Liste tous les postes de travail.
     * GET /api/machines
     */
    @GetMapping("/machines")
    public ResponseEntity<List<MachineState>> getAllMachines() {
        return ResponseEntity.ok(machineService.getAllMachines());
    }

    /**
     * Détail d'un poste par son identifiant.
     * GET /api/machines/{idPoste}
     */
    @GetMapping("/machines/{idPoste}")
    public ResponseEntity<MachineState> getMachine(@PathVariable String idPoste) {
        return machineService.getMachineById(idPoste)
                .map(ResponseEntity::ok)
                .orElse(ResponseEntity.notFound().build());
    }

    /**
     * Postes en alerte (WARN ou CRITICAL).
     * GET /api/alerts
     */
    @GetMapping("/alerts")
    public ResponseEntity<Map<String, Object>> getAlerts() {
        List<MachineState> alerts = machineService.getAlerts();
        return ResponseEntity.ok(Map.of(
                "count",  alerts.size(),
                "alerts", alerts
        ));
    }
}
