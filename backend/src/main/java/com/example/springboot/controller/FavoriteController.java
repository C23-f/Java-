package com.example.springboot.controller;

import com.example.springboot.common.Result;
import com.example.springboot.entity.Favorite;
import com.example.springboot.service.FavoriteService;
import org.springframework.web.bind.annotation.*;
import jakarta.annotation.Resource;
import java.util.List;
import java.util.Map;

@RestController
@RequestMapping("/api/favorite")
public class FavoriteController {

    @Resource
    private FavoriteService favoriteService;

    // 添加收藏
    @PostMapping("/add")
    public Result<?> add(@RequestBody Favorite favorite){
        // 这里可以从token解析userId，前端传objectType、objectId、remark
        Favorite exist = favoriteService.getExistFavorite(favorite.getUserId(), favorite.getObjectType(), favorite.getObjectId());
        if(exist != null){
            return Result.error("已收藏，不可重复添加");
        }
        int rows = favoriteService.addFavorite(favorite);
        if(rows>0){
            return Result.success("收藏成功");
        }else{
            return Result.error("收藏失败");
        }
    }

    // 删除收藏
    @DeleteMapping("/delete")
    public Result<?> delete(@RequestParam Integer userId,
                            @RequestParam String objectType,
                            @RequestParam Integer objectId){
        int rows = favoriteService.removeFavorite(userId,objectType,objectId);
        return Result.success("取消收藏成功");
    }

    // 查询我的收藏
    @GetMapping("/list")
    public Result<List<Favorite>> list(@RequestParam Integer userId){
        List<Favorite> list = favoriteService.getMyFavorite(userId);
        return Result.success(list);
    }

        // 判断是否收藏
    @GetMapping("/isCollect")
    public Result<Boolean> isCollect(@RequestParam Integer userId,
                                     @RequestParam String objectType,
                                     @RequestParam Integer objectId){
        Favorite exist = favoriteService.getExistFavorite(userId, objectType, objectId);
        return Result.success(exist != null);
    }

    // 批量删除收藏（收藏面板批量勾选删除）
    // POST /api/favorite/batchDelete  body: { "userId": 1, "ids": [1,2,3] }
    @PostMapping("/batchDelete")
    public Result<?> batchDelete(@RequestBody Map<String, Object> body){
        Integer userId = (Integer) body.get("userId");
        @SuppressWarnings("unchecked")
        List<Integer> ids = (List<Integer>) body.get("ids");
        if (userId == null || ids == null || ids.isEmpty()) {
            return Result.error("参数不完整：需要 userId 和 ids");
        }
        int rows = favoriteService.removeBatch(userId, ids);
        return Result.success("成功删除 " + rows + " 条收藏");
    }

}
