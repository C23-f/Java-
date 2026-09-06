package com.example.springboot.entity;


import lombok.Data;

/**
 * 15分钟生活圈空间分析返回VO
 */
@Data
public class SpatialCircleVO {
    /**
     * 小区id
     */
    private Long communityId;
    /**
     * 小区名称
     */
    private String communityName;
    /**
     * 设施分类id
     */
    private Long categoryId;
    /**
     * 分类名称
     */
    private String categoryName;
    /**
     * 缓冲区内设施数量
     */
    private Integer facilityCount;
    /**
     * 缓冲区半径(米)
     */
    private Integer bufferRadius;
}
