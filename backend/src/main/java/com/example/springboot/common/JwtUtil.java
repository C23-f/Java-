package com.example.springboot.common;

import io.jsonwebtoken.Claims;
import io.jsonwebtoken.Jwts;
import io.jsonwebtoken.SignatureAlgorithm;
import io.jsonwebtoken.security.Keys;

import javax.crypto.SecretKey;
import java.nio.charset.StandardCharsets;
import java.util.Date;

/**
 * JWT 令牌工具类
 * 登录成功后签发令牌，后续请求通过 Authorization 请求头携带，拦截器负责校验
 */
public class JwtUtil {

    /** 签名密钥：至少 32 字节，生产环境应放到配置文件并妥善保管 */
    private static final String SECRET = "LifeCircle-2026-Secret-Key-For-JWT-Signature-@Admin!";
    /** 令牌有效期：24 小时 */
    private static final long EXPIRE_MILLIS = 24 * 60 * 60 * 1000L;

    private static SecretKey getKey() {
        return Keys.hmacShaKeyFor(SECRET.getBytes(StandardCharsets.UTF_8));
    }

    /**
     * 生成令牌
     */
    public static String generateToken(Integer userId, String username, String roleCode) {
        Date now = new Date();
        return Jwts.builder()
                .setSubject(String.valueOf(userId))
                .claim("username", username)
                .claim("roleCode", roleCode)
                .setIssuedAt(now)
                .setExpiration(new Date(now.getTime() + EXPIRE_MILLIS))
                .signWith(getKey(), SignatureAlgorithm.HS256)
                .compact();
    }

    /**
     * 解析令牌，令牌无效或已过期会抛异常
     */
    public static Claims parseToken(String token) {
        return Jwts.parserBuilder()
                .setSigningKey(getKey())
                .build()
                .parseClaimsJws(token)
                .getBody();
    }
}
