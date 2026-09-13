package com.example.springboot.service;

import com.baomidou.mybatisplus.extension.service.IService;
import com.example.springboot.entity.Favorite;

public interface FavoriteService extends IService<Favorite> {

    /**
     * 添加收藏
     */
    boolean addFavorite(Favorite favorite);

    /**
     * 取消收藏
     */
    boolean removeFavorite(Integer userId, String objectType, Integer objectId);
}
