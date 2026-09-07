package com.example.springboot.service.impl;

import com.example.springboot.common.BizException;
import com.example.springboot.entity.CommunityStatsVO;
import com.example.springboot.entity.Facility;
import com.example.springboot.mapper.FacilityMapper;
import com.example.springboot.service.FacilitySpatialService;
import org.springframework.stereotype.Service;
import jakarta.annotation.Resource;
import java.util.List;

@Service
public class FacilitySpatialServiceImpl implements FacilitySpatialService {

    @Resource
    private FacilityMapper facilityMapper;

    @Override
    public List<Facility> listFacilityByBounds(Double minLng, Double maxLng, Double minLat, Double maxLat) {
        return facilityMapper.selectFacilityByBounds(minLng, maxLng, minLat, maxLat);
    }

    @Override
    public List<Facility> listFacilityByPointBuffer(Double lng, Double lat, Integer radiusM) {
        return facilityMapper.selectFacilityByPointBuffer(lng, lat, radiusM);
    }

@Override
public List<CommunityStatsVO> getPointBufferStats(Double longitude, Double latitude, Integer radius) {
    // 非空校验
    if (longitude == null || latitude == null || radius == null) {
        throw new BizException("经纬度和缓冲区半径参数不能为空");
    }
    // 经度合法范围校验
    if (longitude < -180 || longitude > 180) {
        throw new BizException("经度参数不合法，有效范围为 -180 ~ 180");
    }
    // 纬度合法范围校验
    if (latitude < -90 || latitude > 90) {
        throw new BizException("纬度参数不合法，有效范围为 -90 ~ 90");
    }
    // 半径范围校验
    if (radius <= 0) {
        throw new BizException("缓冲区半径必须大于0");
    }
    if (radius > 5000) {
        throw new BizException("缓冲区半径不能超过5000米，避免查询性能问题");
    }

    return facilityMapper.selectPointBufferStats(longitude, latitude, radius);
}


}
