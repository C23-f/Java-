package com.example.springboot.mapper;

import com.example.springboot.entity.Role;
import org.apache.ibatis.annotations.Param;

import java.util.List;

/**
 * 角色数据访问层
 */
public interface RoleMapper {

    List<Role> findAll();

    Role findById(@Param("id") Integer id);

    int insert(Role role);

    int update(Role role);

    int delete(@Param("id") Integer id);
}
