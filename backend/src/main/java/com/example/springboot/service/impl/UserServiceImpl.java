package com.example.springboot.service.impl;

import com.example.springboot.common.BizException;
import com.example.springboot.common.JwtUtil;
import com.example.springboot.common.PasswordUtil;
import com.example.springboot.common.UserContext;
import com.example.springboot.entity.User;
import com.example.springboot.mapper.UserMapper;
import com.example.springboot.service.UserService;
import org.springframework.stereotype.Service;

import jakarta.annotation.Resource;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

@Service
public class UserServiceImpl implements UserService {

    @Resource
    private UserMapper userMapper;

    @Override
    public Map<String, Object> login(String username, String password) {
        User user = userMapper.findByUsername(username);
        if (user == null || !PasswordUtil.matches(password, user.getPassword())) {
            throw new BizException("用户名或密码错误");
        }
        if (user.getStatus() == null || user.getStatus() != 1) {
            throw new BizException("该账号已被禁用，请联系管理员");
        }

        // 签发 JWT 令牌
        String token = JwtUtil.generateToken(user.getUserId(), user.getUsername(), user.getRoleCode());

        // 返回数据中不携带密码
        user.setPassword(null);
        Map<String, Object> data = new HashMap<>();
        data.put("token", token);
        data.put("user", user);
        return data;
    }

    @Override
    public void register(User user) {
        // 1. 校验参数
        if (user.getUsername() == null || user.getUsername().trim().isEmpty()) {
            throw new BizException("用户名不能为空");
        }
        if (user.getPassword() == null || user.getPassword().isEmpty()) {
            throw new BizException("密码不能为空");
        }
        String username = user.getUsername().trim();
        // 2. 检查用户名是否已存在
        if (userMapper.findByUsername(username) != null) {
            throw new BizException("用户名已存在");
        }
        // 3. 组装数据
        user.setUsername(username);
        user.setPassword(PasswordUtil.encrypt(user.getPassword()));
        // 注册用户默认角色：访客(role_id=3)，只读权限；管理员可后续升级
        user.setRoleId(3);
        user.setStatus(1);
        // 4. 插入数据库（复用已有的 insert）
        userMapper.insert(user);
    }

    @Override
    public User getCurrentUser() {
        User current = UserContext.get();
        if (current == null || current.getUserId() == null) {
            throw new BizException("未登录或登录已过期");
        }
        User user = userMapper.findById(current.getUserId());
        if (user == null) {
            throw new BizException("用户不存在");
        }
        user.setPassword(null);
        return user;
    }

    @Override
    public List<User> listAll() {
        List<User> list = userMapper.findAll();
        list.forEach(u -> u.setPassword(null));
        return list;
    }

    @Override
    public User getById(Integer id) {
        User user = userMapper.findById(id);
        if (user == null) {
            throw new BizException("用户不存在");
        }
        user.setPassword(null);
        return user;
    }

    @Override
    public void add(User user) {
        if (user.getUsername() == null || user.getUsername().trim().isEmpty()) {
            throw new BizException("用户名不能为空");
        }
        if (user.getPassword() == null || user.getPassword().isEmpty()) {
            throw new BizException("密码不能为空");
        }
        if (userMapper.findByUsername(user.getUsername().trim()) != null) {
            throw new BizException("用户名已存在");
        }
        if (user.getRoleId() == null) {
            throw new BizException("请选择角色");
        }
        user.setUsername(user.getUsername().trim());
        // 密码加密后入库
        user.setPassword(PasswordUtil.encrypt(user.getPassword()));
        // 默认启用
        if (user.getStatus() == null) {
            user.setStatus(1);
        }
        userMapper.insert(user);
    }

    @Override
    public void update(User user) {
        if (user.getUserId() == null) {
            throw new BizException("缺少用户ID");
        }
        User exist = userMapper.findById(user.getUserId());
        if (exist == null) {
            throw new BizException("用户不存在");
        }
        // 用户名不可修改，防止与唯一约束冲突
        user.setUsername(null);
        // 密码为空表示不修改密码
        if (user.getPassword() != null && !user.getPassword().isEmpty()) {
            user.setPassword(PasswordUtil.encrypt(user.getPassword()));
        } else {
            user.setPassword(null);
        }
        userMapper.update(user);
    }

    @Override
    public void delete(Integer id) {
        User current = UserContext.get();
        if (current != null && id.equals(current.getUserId())) {
            throw new BizException("不能删除当前登录的账号");
        }
        if (userMapper.findById(id) == null) {
            throw new BizException("用户不存在");
        }
        userMapper.delete(id);
    }
}
