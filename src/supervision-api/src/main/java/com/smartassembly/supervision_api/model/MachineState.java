package com.smartassembly.supervision_api.model;

/**
 * Représente l'état d'un poste de travail lu depuis DynamoDB (table machine_state).
 */
public class MachineState {

    private String idPoste;
    private String statut;        // OK | WARN | CRITICAL
    private String anomalieType;  // VIBRATION | TEMPERATURE | PRESSION | null
    private String vibrationLast;
    private String temperatureLast;
    private String pressionLast;
    private String timestamp;

    public MachineState() {}

    // ── Getters & Setters ─────────────────────────────────

    public String getIdPoste()           { return idPoste; }
    public void setIdPoste(String v)     { this.idPoste = v; }

    public String getStatut()            { return statut; }
    public void setStatut(String v)      { this.statut = v; }

    public String getAnomalieType()      { return anomalieType; }
    public void setAnomalieType(String v){ this.anomalieType = v; }

    public String getVibrationLast()     { return vibrationLast; }
    public void setVibrationLast(String v){ this.vibrationLast = v; }

    public String getTemperatureLast()   { return temperatureLast; }
    public void setTemperatureLast(String v){ this.temperatureLast = v; }

    public String getPressionLast()      { return pressionLast; }
    public void setPressionLast(String v){ this.pressionLast = v; }

    public String getTimestamp()         { return timestamp; }
    public void setTimestamp(String v)   { this.timestamp = v; }
}
