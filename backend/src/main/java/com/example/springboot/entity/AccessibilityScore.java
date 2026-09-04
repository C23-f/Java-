package com.example.springboot.entity;

import lombok.Data;
import java.math.BigDecimal;
import java.time.LocalDateTime;

@Data
public class AccessibilityScore {
    private Integer scoreId;
    private Integer communityId;
    private Integer bufferRadius;
    private BigDecimal totalScore;
    private String scoreLevel;
    private Integer facilityCount;
    private Integer categoryCount;
    private String scoreDetail;
    private LocalDateTime analyzeTime;
}
