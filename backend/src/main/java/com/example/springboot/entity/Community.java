package com.example.springboot.entity;

import lombok.Data;
import java.time.LocalDateTime;

@Data
public class Community {
    private Integer communityId;
    private String communityName;
    private String address;
    private Integer regionId;
    private Double longitude;
    private Double latitude;
    private Integer houseCount;
    private Integer buildYear;
    private Double walkSpeed;
    private String description;
    private LocalDateTime createTime;
    private LocalDateTime updateTime;
}
