package com.example.springboot.entity;

import lombok.Data;

import java.time.LocalDateTime;

/**
 * 角色实体，对应数据库表 sys_role
 */
@Data
public class Role {

    private Integer roleId;
    /** 角色编码 admin/operator/viewer */
    private String roleCode;
    /** 角色名称 */
    private String roleName;
    private String description;
    private LocalDateTime createTime;
}
