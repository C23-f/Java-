package com.example.springboot.controller;

import com.example.springboot.common.BizException;
import com.example.springboot.common.Result;
import com.example.springboot.entity.User;
import com.example.springboot.service.UserService;
import org.springframework.web.bind.annotation.*;

import jakarta.annotation.Resource;
import java.util.List;
import java.util.Map;

/**
 * 用户 Controller（登录 / 用户管理）
 *
 * 登录：POST /api/user/login   { "username": "admin", "password": "123456" }
 * 退出：POST /api/user/logout
 * 我的信息：GET /api/user/info   （需携带令牌）
 * 用户列表：GET /api/user/list   （仅 admin）
 * 用户详情：GET /api/user/{id}   （仅 admin）
 * 新增用户：POST /api/user       （仅 admin）
 * 修改用户：PUT /api/user        （仅 admin）
 * 删除用户：DELETE /api/user/{id}（仅 admin）
 */
@RestController
@RequestMapping("/api/user")
public class UserController {

    @Resource
    private UserService userService;

    /** 登录（无需令牌，拦截器已放行） */
    @PostMapping("/login")
    public Result<Map<String, Object>> login(@RequestBody Map<String, String> body) {
        String username = body.get("username");
        String password = body.get("password");
        if (username == null || username.trim().isEmpty() || password == null || password.isEmpty()) {
            throw new BizException("用户名和密码不能为空");
        }
        return Result.success(userService.login(username.trim(), password));
    }

    /** 退出登录（JWT 无状态，前端丢弃令牌即可） */
    @PostMapping("/logout")
    public Result<String> logout() {
        return Result.success("退出成功");
    }

    /** 当前登录用户信息 */
    @GetMapping("/info")
    public Result<User> info() {
        return Result.success(userService.getCurrentUser());
    }

    /** 用户列表 */
    @GetMapping("/list")
    public Result<List<User>> list() {
        return Result.success(userService.listAll());
    }

    /** 用户详情 */
    @GetMapping("/{id:\\d+}")
    public Result<User> getById(@PathVariable Integer id) {
        return Result.success(userService.getById(id));
    }

    /** 新增用户 */
    @PostMapping
    public Result<String> add(@RequestBody User user) {
        userService.add(user);
        return Result.success("新增成功");
    }

    /** 修改用户 */
    @PutMapping
    public Result<String> update(@RequestBody User user) {
        userService.update(user);
        return Result.success("修改成功");
    }

    /** 删除用户 */
    @DeleteMapping("/{id:\\d+}")
    public Result<String> delete(@PathVariable Integer id) {
        userService.delete(id);
        return Result.success("删除成功");
    }
}
