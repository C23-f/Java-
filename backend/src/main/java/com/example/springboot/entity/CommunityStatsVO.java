package com.example.springboot.entity;

import lombok.Data;
import java.math.BigDecimal;

@Data
public class CommunityStatsVO {
    private String categoryCode;
    private String categoryName;
    private BigDecimal weight;
    private Integer facilityCount;
}
