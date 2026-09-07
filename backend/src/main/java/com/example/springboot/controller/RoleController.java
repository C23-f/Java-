package com.example.springboot.controller;

import com.example.springboot.common.Result;
import com.example.springboot.entity.Role;
import com.example.springboot.service.RoleService;
import org.springframework.web.bind.annotation.*;

import jakarta.annotation.Resource;
import java.util.List;

/**
 * 角色 Controller（角色管理，全部仅 admin 可访问，由拦截器校验）
 *
 * 角色列表：GET /api/role/list
 * 角色详情：GET /api/role/{id}
 * 新增角色：POST /api/role
 * 修改角色：PUT /api/role
 * 删除角色：DELETE /api/role/{id}
 */
@RestController
@RequestMapping("/api/role")
public class RoleController {

    @Resource
    private RoleService roleService;

    @GetMapping("/list")
    public Result<List<Role>> list() {
        return Result.success(roleService.listAll());
    }

    @GetMapping("/{id:\\d+}")
    public Result<Role> getById(@PathVariable Integer id) {
        return Result.success(roleService.getById(id));
    }

    @PostMapping
    public Result<String> add(@RequestBody Role role) {
        roleService.add(role);
        return Result.success("新增成功");
    }

    @PutMapping
    public Result<String> update(@RequestBody Role role) {
        roleService.update(role);
        return Result.success("修改成功");
    }

    @DeleteMapping("/{id:\\d+}")
    public Result<String> delete(@PathVariable Integer id) {
        roleService.delete(id);
        return Result.success("删除成功");
    }
}
