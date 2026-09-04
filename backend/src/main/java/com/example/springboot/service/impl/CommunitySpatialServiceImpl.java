package com.example.springboot.service.impl;

import com.example.springboot.entity.AccessibilityScore;
import com.example.springboot.entity.Community;
import com.example.springboot.entity.CommunityStatsVO;
import com.example.springboot.mapper.CommunityMapper;
import com.example.springboot.service.CommunitySpatialService;
import org.springframework.stereotype.Service;
import jakarta.annotation.Resource;
import java.util.ArrayList;
import java.util.List;

@Service
public class CommunitySpatialServiceImpl implements CommunitySpatialService {

    @Resource
    private CommunityMapper communityMapper;

    @Override
    public List<Community> listAllCommunity() {
        return communityMapper.selectAllCommunity();
    }

    @Override
    public List<CommunityStatsVO> getCommunity15MinStats(Integer communityId, Integer radiusM) {
        return communityMapper.callStatsProc(communityId, radiusM);
    }

    @Override
    public AccessibilityScore calcSingleScore(Integer communityId, Integer radiusM, Integer perCategoryCap) {
        return communityMapper.callCalcScoreProc(communityId, radiusM, perCategoryCap);
    }

    @Override
    public List<AccessibilityScore> batchCalcAllCommunity(Integer radiusM, Integer perCategoryCap) {
        List<Community> communityList = communityMapper.selectAllCommunity();
        List<AccessibilityScore> resultList = new ArrayList<>();
        for (Community community : communityList) {
            AccessibilityScore score = communityMapper.callCalcScoreProc(community.getCommunityId(), radiusM, perCategoryCap);
            if (score != null) {
                resultList.add(score);
            }
        }
        return resultList;
    }
}
