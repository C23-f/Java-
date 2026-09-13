package com.example.springboot.mapper;

import com.baomidou.mybatisplus.core.mapper.BaseMapper;
import com.example.springboot.entity.Favorite;
import org.apache.ibatis.annotations.Mapper;
import org.apache.ibatis.annotations.Param;
import java.util.List;

@Mapper
public interface FavoriteMapper extends BaseMapper<Favorite> {
    int insertCustom(Favorite favorite);
    int deleteByUserAndObj(@Param("userId") Integer userId, @Param("objectType") String objectType, @Param("objectId") Integer objectId);
    List<Favorite> selectByUserId(@Param("userId") Integer userId);
    Favorite selectExist(@Param("userId") Integer userId, @Param("objectType") String objectType, @Param("objectId") Integer objectId);

    // 批量删除收藏（按收藏记录id列表，且仅限当前用户，防止越权删除他人收藏）
    int deleteBatch(@Param("userId") Integer userId, @Param("ids") List<Integer> ids);
}
