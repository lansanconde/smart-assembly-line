package com.smartassembly.supervision_api.service;


import com.smartassembly.supervision_api.model.MachineState;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;
import software.amazon.awssdk.regions.Region;
import software.amazon.awssdk.services.dynamodb.DynamoDbClient;
import software.amazon.awssdk.services.dynamodb.model.*;


import java.util.List;
import java.util.Map;
import java.util.Optional;

/**
 * Lit les états des postes depuis DynamoDB (lecture seule — principe du moindre privilège).
 * Les credentials sont injectés automatiquement via le Task Role ECS (pas de clé dans le code).
 */
@Service
public class MachineService {

    private final DynamoDbClient dynamoDb;
    private final String tableName;

    public MachineService(
            @Value("${aws.region:eu-west-3}") String region,
            @Value("${aws.dynamodb.table-name:machine_state}") String tableName) {

        // Sur ECS Fargate, le SDK récupère automatiquement les credentials
        // depuis le Task Metadata Endpoint (Task Role) — aucune clé AWS dans le code
        this.dynamoDb = DynamoDbClient.builder()
                .region(Region.of(region))
                .build();
        this.tableName = tableName;
    }

    /**
     * Retourne tous les postes de travail.
     */
    public List<MachineState> getAllMachines() {
        ScanResponse response = dynamoDb.scan(
                ScanRequest.builder().tableName(tableName).build()
        );
        return response.items().stream()
                .map(this::toMachineState)
                .toList();
    }

    /**
     * Retourne un poste par son identifiant.
     */
    public Optional<MachineState> getMachineById(String idPoste) {
        GetItemResponse response = dynamoDb.getItem(
                GetItemRequest.builder()
                        .tableName(tableName)
                        .key(Map.of("id_poste", AttributeValue.fromS(idPoste)))
                        .build()
        );
        if (!response.hasItem() || response.item().isEmpty()) {
            return Optional.empty();
        }
        return Optional.of(toMachineState(response.item()));
    }

    /**
     * Retourne uniquement les postes en alerte (WARN ou CRITICAL).
     */
    public List<MachineState> getAlerts() {
        // Scan avec FilterExpression — acceptable pour un lab (table petite)
        // En production : GSI sur le champ statut pour éviter le full scan
        ScanResponse response = dynamoDb.scan(
                ScanRequest.builder()
                        .tableName(tableName)
                        .filterExpression("#s = :warn OR #s = :critical")
                        .expressionAttributeNames(Map.of("#s", "statut"))
                        .expressionAttributeValues(Map.of(
                                ":warn",     AttributeValue.fromS("WARN"),
                                ":critical", AttributeValue.fromS("CRITICAL")
                        ))
                        .build()
        );
        return response.items().stream()
                .map(this::toMachineState)
                .toList();
    }

    // ── Mapping DynamoDB Item → MachineState ──────────────

    private MachineState toMachineState(Map<String, AttributeValue> item) {
        MachineState ms = new MachineState();
        ms.setIdPoste(getString(item, "id_poste"));
        ms.setStatut(getString(item, "statut"));
        ms.setAnomalieType(getString(item, "anomalie_type"));
        ms.setVibrationLast(getString(item, "vibration_last"));
        ms.setTemperatureLast(getString(item, "temperature_last"));
        ms.setPressionLast(getString(item, "pression_last"));
        ms.setTimestamp(getString(item, "timestamp"));
        return ms;
    }

    private String getString(Map<String, AttributeValue> item, String key) {
        AttributeValue val = item.get(key);
        return (val != null && val.s() != null) ? val.s() : null;
    }
}
