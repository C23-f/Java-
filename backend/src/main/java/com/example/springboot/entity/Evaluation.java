package com.example.springboot.entity;

import java.math.BigDecimal;
import java.time.LocalDateTime;

import com.baomidou.mybatisplus.annotation.IdType;
import com.baomidou.mybatisplus.annotation.TableId;
import com.baomidou.mybatisplus.annotation.TableName;
import lombok.Data;

@Data
@TableName("[evaluation]")
public class Evaluation {

    @TableId(type = IdType.AUTO)
    private Integer id;

    private String objectType;   // community / facility
    private Integer objectId;

    private Integer userId;
    private BigDecimal score;    // 星级 0‑5

    private String content;
    private Integer status;      //0待审核 1通过 2驳回
    private String rejectReason;

    private LocalDateTime createTime;
    private LocalDateTime auditTime;
    private Integer auditorId;
}
