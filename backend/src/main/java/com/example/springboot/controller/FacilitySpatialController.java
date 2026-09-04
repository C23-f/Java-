package com.example.springboot.controller;

import com.example.springboot.common.Result;
import com.example.springboot.entity.Facility;
import com.example.springboot.service.FacilitySpatialService;
import org.springframework.web.bind.annotation.*;
import jakarta.annotation.Resource;
import java.util.List;

@RestController
@RequestMapping("/api/facility")
public class FacilitySpatialController {

    @Resource
    private FacilitySpatialService facilitySpatialService;

    // 矩形框选范围内设施查询
    @GetMapping("/bounds")
    public Result<List<Facility>> listByBounds(@RequestParam Double minLng,
                                               @RequestParam Double maxLng,
                                               @RequestParam Double minLat,
                                               @RequestParam Double maxLat) {
        List<Facility> list = facilitySpatialService.listFacilityByBounds(minLng, maxLng, minLat, maxLat);
        return Result.success(list);
    }

    // 指定点位周边N米范围内设施查询
    @GetMapping("/buffer")
    public Result<List<Facility>> listByBuffer(@RequestParam Double lng,
                                               @RequestParam Double lat,
                                               @RequestParam(defaultValue = "1000") Integer radius) {
        List<Facility> list = facilitySpatialService.listFacilityByPointBuffer(lng, lat, radius);
        return Result.success(list);
    }
}
