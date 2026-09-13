package com.example.springboot.mapper;
import com.example.springboot.entity.Evaluation;
import org.apache.ibatis.annotations.Mapper;
import org.apache.ibatis.annotations.Param;
import java.util.List;

@Mapper
public interface EvaluationMapper {
    int auditEvaluation(
            @Param("id") Integer id,
            @Param("status") Integer status,
            @Param("rejectReason") String rejectReason,
            @Param("auditorId") Integer auditorId
    );
    int insert(Evaluation evaluation);
    
    // 新增这一行
    List<Evaluation> selectEvaluationList(@Param("status") Integer status);
    // 根据id查询评价详情
    Evaluation selectById(Integer id);
    // 删除评价
    int deleteById(Integer id);
}
