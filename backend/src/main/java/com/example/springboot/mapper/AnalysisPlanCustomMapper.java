package com.example.springboot.mapper;
import com.example.springboot.entity.AnalysisPlan;
import org.apache.ibatis.annotations.Mapper;
import org.apache.ibatis.annotations.Param;
import org.apache.ibatis.annotations.Select;
import java.util.List;

@Mapper
public interface AnalysisPlanCustomMapper {
    @Select("""
        SELECT id,user_id,plan_name,start_type,start_lon,start_lat,start_community_id,time_min,
        facility_types,weights,price_min,price_max,create_time
        FROM analysis_plan
        WHERE user_id = #{userId}
        ORDER BY create_time DESC
    """)
    List<AnalysisPlan> getPlanListByUserId(@Param("userId") Integer userId);
}
