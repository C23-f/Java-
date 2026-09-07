package com.example.springboot.service;

import com.example.springboot.entity.User;

import java.util.List;
import java.util.Map;

/**
 * 用户业务接口
 */
public interface UserService {

    /** 登录：校验账号密码，返回 token + 用户信息 */
    Map<String, Object> login(String username, String password);

    /** 用户注册（无需登录，默认角色为访客） */
    void register(User user);

    /** 获取当前登录用户完整信息（从数据库查） */
    User getCurrentUser();

    List<User> listAll();

    User getById(Integer id);

    void add(User user);

    void update(User user);

    void delete(Integer id);
}
