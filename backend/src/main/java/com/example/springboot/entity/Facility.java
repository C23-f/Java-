package com.example.springboot.entity;

import lombok.Data;
import java.time.LocalDateTime;

@Data
public class Facility {
    private Integer facilityId;
    private String facilityName;
    private Integer categoryId;
    private String address;
    private Double longitude;
    private Double latitude;
    private String source;
    private String poiId;
    private Short status;
    private LocalDateTime createTime;
}
