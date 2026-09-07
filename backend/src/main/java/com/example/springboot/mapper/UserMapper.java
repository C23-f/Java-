package com.example.springboot.mapper;

import com.example.springboot.entity.User;
import org.apache.ibatis.annotations.Param;

import java.util.List;

/**
 * 用户数据访问层
 */
public interface UserMapper {

    /** 按用户名查询（联表带出角色信息） */
    User findByUsername(@Param("username") String username);

    /** 按ID查询 */
    User findById(@Param("id") Integer id);

    /** 查询全部用户 */
    List<User> findAll();

    /** 新增用户，返回自增主键到 user.userId */
    int insert(User user);

    /** 更新用户（动态字段） */
    int update(User user);

    /** 删除用户 */
    int delete(@Param("id") Integer id);
}
