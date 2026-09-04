package com.example.springboot.service.impl;

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
}
