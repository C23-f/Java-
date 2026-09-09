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
    public List<Facility> listAll() {
        return facilityMapper.selectAll();
    }

    @Override
    public Facility getById(Integer id) {
        if (id == null) {
            throw new BizException("设施ID不能为空");
        }
        return facilityMapper.selectById(id);
    }

    @Override
    public void add(Facility facility) {
        // 非空校验
        if (facility.getFacilityName() == null || facility.getFacilityName().trim().isEmpty()) {
            throw new BizException("设施名称不能为空");
        }
        if (facility.getCategoryId() == null) {
            throw new BizException("设施分类不能为空");
        }
        // 经纬度范围校验
        validateLngLat(facility.getLongitude(), facility.getLatitude());
        // 状态默认有效
        if (facility.getStatus() == null) {
            facility.setStatus((short) 1);
        }
        int rows = facilityMapper.insert(facility);
        if (rows <= 0) {
            throw new BizException("新增设施失败");
        }
    }

    @Override
    public void edit(Facility facility) {
        if (facility.getFacilityId() == null) {
            throw new BizException("设施ID不能为空");
        }
        // 存在性校验
        Facility exist = facilityMapper.selectById(facility.getFacilityId());
        if (exist == null) {
            throw new BizException("设施不存在，ID=" + facility.getFacilityId());
        }
        if (facility.getFacilityName() == null || facility.getFacilityName().trim().isEmpty()) {
            throw new BizException("设施名称不能为空");
        }
        if (facility.getCategoryId() == null) {
            throw new BizException("设施分类不能为空");
        }
        validateLngLat(facility.getLongitude(), facility.getLatitude());
        int rows = facilityMapper.update(facility);
        if (rows <= 0) {
            throw new BizException("修改设施失败");
        }
    }

    @Override
    public void remove(Integer id) {
        if (id == null) {
            throw new BizException("设施ID不能为空");
        }
        Facility exist = facilityMapper.selectById(id);
        if (exist == null) {
            throw new BizException("设施不存在，ID=" + id);
        }
        int rows = facilityMapper.deleteById(id);
        if (rows <= 0) {
            throw new BizException("删除设施失败");
        }
    }

    /** 经纬度合法范围校验 */
    private void validateLngLat(Double lng, Double lat) {
        if (lng == null || lat == null) {
            throw new BizException("经度和纬度不能为空");
        }
        if (lng < -180 || lng > 180) {
            throw new BizException("经度不合法，有效范围 -180 ~ 180");
        }
        if (lat < -90 || lat > 90) {
            throw new BizException("纬度不合法，有效范围 -90 ~ 90");
        }
    }

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
