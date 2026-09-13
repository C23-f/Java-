package com.example.springboot.controller;
import com.example.springboot.common.Result;
import com.example.springboot.entity.Evaluation;
import com.example.springboot.entity.PageResult;
import com.example.springboot.service.EvaluationService;
import com.example.springboot.common.JwtUtil;
import jakarta.annotation.Resource;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;
import java.util.List;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.PathVariable;
import java.util.Map;





@RestController
@RequestMapping("/api/evaluation")
public class EvaluationController {
    @Resource
    private EvaluationService evaluationService;

    /**
     * 用户提交评价，登录后调用
     * POST /api/evaluation/submit
     */
    @PostMapping("/submit")
public Result<?> submit(
        @RequestBody Evaluation evaluation,
        @RequestHeader("Authorization") String token
){
    // 移除Bearer前缀，解析token拿到登录用户ID
    String realToken = token.replace("Bearer ","");
    Integer userId = JwtUtil.getUserId(realToken);
    // 自动设置userId，前端不需要传user_id
    evaluation.setUserId(userId);
    // ==========新增这一行==========
    evaluation.setStatus(0);
    int rows = evaluationService.insert(evaluation);
    boolean ok = rows > 0;
    return ok ? Result.success() : Result.error("提交评价失败");
}


/**
 * 管理员审核评价
 * POST /api/evaluation/audit
 */
@PostMapping("/audit")
public Result<?> audit(
        @RequestBody Evaluation evaluation,
        @RequestHeader("Authorization") String token
){
    String realToken = token.replace("Bearer ", "");
    Integer auditorId = JwtUtil.getUserId(realToken);
    boolean ok = evaluationService.audit(evaluation.getId(), evaluation.getStatus(), evaluation.getRejectReason(), auditorId);
    return ok ? Result.success() : Result.error("审核失败");
}
/**
 * 查询评价列表
 * GET /api/evaluation/list
 * @param status 可选：0待审核 1通过 2驳回；不传查全部
 */
@GetMapping("/list")
public Result<List<Evaluation>> list(
        @RequestParam(required = false) Integer status
){
    List<Evaluation> list = evaluationService.listEvaluation(status);
    return Result.success(list);
}

    /**
     * 根据ID查询评价详情
     * GET /api/evaluation/{id}
     */
    @GetMapping("/{id}")
    public Result<Evaluation> getById(@PathVariable Integer id){
        Evaluation evaluation = evaluationService.getById(id);
        return Result.success(evaluation);
    }

    /**
     * 删除评价（管理员）
     * DELETE /api/evaluation/{id}
     */
    @DeleteMapping("/{id}")
    public Result<?> delete(@PathVariable Integer id){
        boolean ok = evaluationService.delete(id);
        return ok ? Result.success() : Result.error("删除失败");
    }

    /**
     * 获取当前登录用户自己提交的评价列表
     * GET /api/evaluation/myList
     */
    @GetMapping("/myList")
    public Result<List<Evaluation>> myList(
            @RequestHeader("Authorization") String token
    ){
        String realToken = token.replace("Bearer ","");
        Integer userId = JwtUtil.getUserId(realToken);
        List<Evaluation> list = evaluationService.myListEvaluation(userId);
        return Result.success(list);
    }

    /**
     * 评价统计接口，给前端图表用（待审核/通过/驳回数量）
     * GET /api/evaluation/stats
     */
    @GetMapping("/stats")
    public Result<?> stats(){
        Map<String,Object> data = evaluationService.getEvaluationStats();
        return Result.success(data);
    }

    /**
     * 分页查询评价列表（数据管理页分页展示）
     * GET /api/evaluation/page?status=&page=&size=
     */
    @GetMapping("/page")
    public Result<PageResult<Evaluation>> page(
            @RequestParam(required = false) Integer status,
            @RequestParam(defaultValue = "1") Integer page,
            @RequestParam(defaultValue = "10") Integer size){
        return Result.success(evaluationService.listEvaluationPage(status, page, size));
    }

}
