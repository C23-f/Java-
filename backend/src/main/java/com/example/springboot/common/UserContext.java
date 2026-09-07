package com.example.springboot.common;

import com.example.springboot.entity.User;

/**
 * 当前登录用户上下文
 * 拦截器校验通过后把用户信息放到这里，Controller/Service 里随时取用：
 *     User current = UserContext.get();
 * 请求结束后由拦截器清理，避免线程复用串号
 */
public class UserContext {

    private static final ThreadLocal<User> HOLDER = new ThreadLocal<>();

    public static void set(User user) {
        HOLDER.set(user);
    }

    public static User get() {
        return HOLDER.get();
    }

    public static void clear() {
        HOLDER.remove();
    }
}
