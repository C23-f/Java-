package com.example.springboot.service;

import com.example.springboot.entity.Favorite;
import java.util.List;

public interface FavoriteService {
    int addFavorite(Favorite favorite);
    int removeFavorite(Integer userId, String objectType, Integer objectId);
    List<Favorite> getMyFavorite(Integer userId);
    Favorite getExistFavorite(Integer userId, String objectType, Integer objectId);

    // 批量删除收藏（仅当前用户自己的收藏）
    int removeBatch(Integer userId, List<Integer> ids);
}
