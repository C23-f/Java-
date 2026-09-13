package com.example.springboot.entity;

import java.time.LocalDateTime;

import com.baomidou.mybatisplus.annotation.IdType;
import com.baomidou.mybatisplus.annotation.TableId;
import com.baomidou.mybatisplus.annotation.TableName;
import lombok.Data;

@Data
@TableName("favorite")
public class Favorite {

    @TableId(type = IdType.AUTO)
    private Integer id;

    private Integer userId;
    private String objectType;  // community / facility
    private Integer objectId;

    private String remark;
    private LocalDateTime createTime;
}
