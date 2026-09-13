package com.example.springboot.service.impl;

import com.baomidou.mybatisplus.core.conditions.query.LambdaQueryWrapper;
import com.baomidou.mybatisplus.extension.service.impl.ServiceImpl;
import com.example.springboot.entity.Favorite;
import com.example.springboot.mapper.FavoriteMapper;
import com.example.springboot.service.FavoriteService;
import org.springframework.stereotype.Service;
import java.time.LocalDateTime;

@Service
public class FavoriteServiceImpl extends ServiceImpl<FavoriteMapper, Favorite>
        implements FavoriteService {

    @Override
    public boolean addFavorite(Favorite favorite) {
        favorite.setCreateTime(LocalDateTime.now());
        //数据库有唯一约束 uk_user_obj，重复收藏会抛异常，controller捕获
        return save(favorite);
    }

    @Override
    public boolean removeFavorite(Integer userId, String objectType, Integer objectId) {
        LambdaQueryWrapper<Favorite> wrapper = new LambdaQueryWrapper<>();
        wrapper.eq(Favorite::getUserId, userId)
                .eq(Favorite::getObjectType, objectType)
                .eq(Favorite::getObjectId, objectId);
        return remove(wrapper);
    }
}
