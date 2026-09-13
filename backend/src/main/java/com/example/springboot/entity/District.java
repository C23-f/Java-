package com.example.springboot.entity;

import lombok.Data;

/**
 * 街道行政区实体，对应 district 表
 * boundary 存储街道边界 GeoJSON 文本，前端解析后绘制行政区边界
 */
@Data
public class District {
    private Integer id;
    /** 街道名称 */
    private String name;
    /** 街道边界 GeoJSON */
    private String boundary;
}
