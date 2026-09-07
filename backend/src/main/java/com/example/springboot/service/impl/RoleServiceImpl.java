package com.example.springboot.service.impl;

import com.example.springboot.common.BizException;
import com.example.springboot.entity.Role;
import com.example.springboot.mapper.RoleMapper;
import com.example.springboot.service.RoleService;
import org.springframework.stereotype.Service;

import jakarta.annotation.Resource;
import java.util.List;

/**
 * 角色业务实现
 */
@Service
public class RoleServiceImpl implements RoleService {

    @Resource
    private RoleMapper roleMapper;

    @Override
    public List<Role> listAll() {
        return roleMapper.findAll();
    }

    @Override
    public Role getById(Integer id) {
        Role role = roleMapper.findById(id);
        if (role == null) {
            throw new BizException("角色不存在");
        }
        return role;
    }

    @Override
    public void add(Role role) {
        if (role.getRoleCode() == null || role.getRoleCode().trim().isEmpty()) {
            throw new BizException("角色编码不能为空");
        }
        if (role.getRoleName() == null || role.getRoleName().trim().isEmpty()) {
            throw new BizException("角色名称不能为空");
        }
        role.setRoleCode(role.getRoleCode().trim());
        role.setRoleName(role.getRoleName().trim());
        roleMapper.insert(role);
    }

    @Override
    public void update(Role role) {
        if (role.getRoleId() == null) {
            throw new BizException("缺少角色ID");
        }
        if (roleMapper.findById(role.getRoleId()) == null) {
            throw new BizException("角色不存在");
        }
        roleMapper.update(role);
    }

    @Override
    public void delete(Integer id) {
        if (roleMapper.findById(id) == null) {
            throw new BizException("角色不存在");
        }
        // 角色下还有用户时，外键约束会阻止删除，数据库会抛异常，由全局异常处理器统一提示
        roleMapper.delete(id);
    }
}
