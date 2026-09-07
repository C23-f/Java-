package com.example.springboot.service;

import com.example.springboot.entity.Role;

import java.util.List;

/**
 * 角色业务接口
 */
public interface RoleService {

    List<Role> listAll();

    Role getById(Integer id);

    void add(Role role);

    void update(Role role);

    void delete(Integer id);
}
