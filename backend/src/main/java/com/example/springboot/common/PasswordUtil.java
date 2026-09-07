package com.example.springboot.common;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;

/**
 * 密码工具类
 * 与数据库 init_db.sql 中种子账号的加密方式保持一致：
 *   SQL: CONVERT(NVARCHAR(64), HASHBYTES('SHA2_256', N'123456'), 2)
 * 即对密码的 UTF-16LE 字节做 SHA-256，再转大写十六进制字符串
 */
public class PasswordUtil {

    /**
     * 密码加密：SHA-256(UTF-16LE bytes) -> 大写十六进制
     */
    public static String encrypt(String rawPassword) {
        try {
            MessageDigest digest = MessageDigest.getInstance("SHA-256");
            byte[] hash = digest.digest(rawPassword.getBytes(StandardCharsets.UTF_16LE));
            StringBuilder sb = new StringBuilder();
            for (byte b : hash) {
                sb.append(String.format("%02X", b));
            }
            return sb.toString();
        } catch (NoSuchAlgorithmException e) {
            throw new RuntimeException("SHA-256 算法不可用", e);
        }
    }

    /**
     * 校验密码：加密后与数据库存储值比较
     */
    public static boolean matches(String rawPassword, String storedHash) {
        if (rawPassword == null || storedHash == null) {
            return false;
        }
        return encrypt(rawPassword).equalsIgnoreCase(storedHash);
    }
}
