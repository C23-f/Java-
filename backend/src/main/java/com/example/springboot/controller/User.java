package com.example.springboot.entity;

import lombok.Data;

import java.time.LocalDateTime;

/**
 * 用户实体，对应数据库表 sys_user
 * roleName / roleCode 是通过联表查询得到的角色信息（非表字段）
 */
@Data
public class User {

    private Integer userId;
    private String username;
    private String password;
    private String realName;
    private String phone;
    private Integer roleId;
    /** 1启用 0禁用 */
    private Integer status;
    private LocalDateTime createTime;
    private LocalDateTime updateTime;

    /** 角色名称（联表） */
    private String roleName;
    /** 角色编码 admin/operator/viewer（联表，用于权限判断） */
    private String roleCode;
}
