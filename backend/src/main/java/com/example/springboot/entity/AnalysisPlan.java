package com.example.springboot.entity;
import java.math.BigDecimal;
import java.time.LocalDateTime;
import com.baomidou.mybatisplus.annotation.IdType;
import com.baomidou.mybatisplus.annotation.TableId;
import com.baomidou.mybatisplus.annotation.TableName;
import lombok.Data;
@Data
@TableName("analysis_plan")
public class AnalysisPlan {
    @TableId(type = IdType.AUTO)
    private Integer id;
    private Integer userId;
    private String planName;
    private String startType;   // point / community
    private BigDecimal startLon;
    private BigDecimal startLat;
    private Integer startCommunityId;
    private Integer timeMin;
    private String facilityTypes; // json字符串
    private String weights;       // json字符串
    private BigDecimal priceMin;
    private BigDecimal priceMax;
    private LocalDateTime createTime;
}
