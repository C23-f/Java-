package com.example.springboot.service.impl;

import com.example.springboot.entity.Favorite;
import com.example.springboot.mapper.FavoriteMapper;
import com.example.springboot.service.FavoriteService;
import org.springframework.stereotype.Service;
import jakarta.annotation.Resource;
import java.util.List;

@Service
public class FavoriteServiceImpl implements FavoriteService {

    @Resource
    private FavoriteMapper favoriteMapper;

    @Override
    public int addFavorite(Favorite favorite) {
        // 这里调用自定义方法 insertCustom，不是insert！
        return favoriteMapper.insertCustom(favorite);
    }

    @Override
    public int removeFavorite(Integer userId, String objectType, Integer objectId) {
        return favoriteMapper.deleteByUserAndObj(userId,objectType,objectId);
    }

    @Override
    public List<Favorite> getMyFavorite(Integer userId) {
        return favoriteMapper.selectByUserId(userId);
    }

    @Override
    public Favorite getExistFavorite(Integer userId, String objectType, Integer objectId) {
        return favoriteMapper.selectExist(userId,objectType,objectId);
    }
}
