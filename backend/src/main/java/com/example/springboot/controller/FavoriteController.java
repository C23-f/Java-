package com.example.springboot.controller;

import com.example.springboot.common.Result;
import com.example.springboot.entity.Favorite;
import com.example.springboot.service.FavoriteService;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;
import jakarta.annotation.Resource;

@RestController
@RequestMapping("/api/favorite")
public class FavoriteController {

    @Resource
    private FavoriteService favoriteService;

    @PostMapping("/add")
    public Result<?> add(@RequestBody Favorite favorite){
        boolean ok = favoriteService.addFavorite(favorite);
        return ok ? Result.success() : Result.error("收藏失败");
    }

    @PostMapping("/remove")
    public Result<?> remove(){
        //后续接收参数 userId objectType objectId
        return Result.success();
    }
}
