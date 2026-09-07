package com.example.springboot.entity;

import lombok.Data;

@Data
public class CommunityStatsVO {
    private String categoryCode;
    private String categoryName;
    private Integer weight= 0;
    private Integer facilityCount;
    
}
