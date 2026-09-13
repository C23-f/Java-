package com.example.springboot.controller;

import com.example.springboot.common.BizException;
import com.example.springboot.entity.Community;
import com.example.springboot.entity.Evaluation;
import com.example.springboot.entity.Facility;
import com.example.springboot.entity.Favorite;
import com.example.springboot.mapper.CommunityMapper;
import com.example.springboot.mapper.EvaluationMapper;
import com.example.springboot.mapper.FacilityMapper;
import com.example.springboot.mapper.FavoriteMapper;
import jakarta.annotation.Resource;
import jakarta.servlet.http.HttpServletResponse;
import org.apache.poi.ss.usermodel.Cell;
import org.apache.poi.ss.usermodel.Row;
import org.apache.poi.ss.usermodel.Sheet;
import org.apache.poi.xssf.usermodel.XSSFWorkbook;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import java.io.IOException;
import java.io.OutputStream;
import java.net.URLEncoder;
import java.nio.charset.StandardCharsets;
import java.util.List;

/**
 * Excel 导出 Controller
 * 提供：小区列表 / 设施列表 / 评价报表 / 个人收藏 / 可达分析结果 的 xlsx 下载
 * 所有接口需登录访问（JwtInterceptor 默认校验）
 */
@RestController
@RequestMapping("/api/export")
public class ExportController {

    @Resource
    private CommunityMapper communityMapper;
    @Resource
    private FacilityMapper facilityMapper;
    @Resource
    private EvaluationMapper evaluationMapper;
    @Resource
    private FavoriteMapper favoriteMapper;

    /** 导出小区列表 */
    @GetMapping("/communities")
    public void exportCommunities(HttpServletResponse response) throws IOException {
        List<Community> list = communityMapper.selectAllCommunity();
        Object[][] rows = list.stream().map(c -> new Object[]{
                c.getCommunityId(), c.getCommunityName(), c.getAddress(),
                c.getPrice(), c.getAvgScore(), c.getHousehold(), c.getPopulation(),
                c.getLongitude(), c.getLatitude(), c.getDistrictName()
        }).toArray(Object[][]::new);
        writeXlsx(response, "小区列表",
                new String[]{"ID", "小区名称", "地址", "房价(元/㎡)", "平均分", "户数", "人口", "经度", "纬度", "所属街道"},
                rows);
    }

    /** 导出设施列表 */
    @GetMapping("/facilities")
    public void exportFacilities(HttpServletResponse response) throws IOException {
        List<Facility> list = facilityMapper.selectAll();
        Object[][] rows = list.stream().map(f -> new Object[]{
                f.getFacilityId(), f.getFacilityName(), f.getCategoryName(),
                f.getAddress(), f.getAvgScore(), f.getPhone(), f.getOpenTime(),
                f.getLongitude(), f.getLatitude()
        }).toArray(Object[][]::new);
        writeXlsx(response, "设施列表",
                new String[]{"ID", "设施名称", "分类", "地址", "评分", "电话", "开放时间", "经度", "纬度"},
                rows);
    }

    /** 导出评价报表 */
    @GetMapping("/evaluations")
    public void exportEvaluations(HttpServletResponse response) throws IOException {
        List<Evaluation> list = evaluationMapper.selectEvaluationList(null);
        Object[][] rows = list.stream().map(e -> new Object[]{
                e.getId(),
                "community".equals(e.getObjectType()) ? "小区" : "设施",
                e.getObjectId(), e.getUserId(), e.getScore(), e.getContent(),
                evalStatus(e.getStatus()), e.getRejectReason(), e.getCreateTime()
        }).toArray(Object[][]::new);
        writeXlsx(response, "评价报表",
                new String[]{"ID", "评价对象类型", "对象ID", "用户ID", "评分", "内容", "审核状态", "驳回理由", "提交时间"},
                rows);
    }

    /** 导出个人收藏数据集 */
    @GetMapping("/favorites")
    public void exportFavorites(@RequestParam Integer userId, HttpServletResponse response) throws IOException {
        List<Favorite> list = favoriteMapper.selectByUserId(userId);
        Object[][] rows = list.stream().map(f -> new Object[]{
                f.getId(),
                "community".equals(f.getObjectType()) ? "小区" : "设施",
                f.getObjectId(), f.getRemark(), f.getCreateTime()
        }).toArray(Object[][]::new);
        writeXlsx(response, "我的收藏",
                new String[]{"ID", "收藏类型", "对象ID", "备注标签", "收藏时间"},
                rows);
    }

    /** 导出可达性分析结果（指定点位缓冲区内的设施清单） */
    @GetMapping("/analysis")
    public void exportAnalysis(@RequestParam Double lng,
                               @RequestParam Double lat,
                               @RequestParam(defaultValue = "1000") Integer radius,
                               HttpServletResponse response) throws IOException {
        if (lng == null || lat == null || radius == null) {
            throw new BizException("经纬度和缓冲区半径参数不能为空");
        }
        if (lng < -180 || lng > 180 || lat < -90 || lat > 90) {
            throw new BizException("经纬度不合法");
        }
        if (radius <= 0 || radius > 5000) {
            throw new BizException("缓冲区半径必须大于0且不超过5000米");
        }
        List<Facility> list = facilityMapper.selectFacilityByPointBuffer(lng, lat, radius);
        Object[][] rows = list.stream().map(f -> new Object[]{
                f.getFacilityId(), f.getFacilityName(), f.getCategoryName(),
                f.getAddress(), f.getAvgScore(), f.getDistance()
        }).toArray(Object[][]::new);
        writeXlsx(response, "可达分析结果",
                new String[]{"ID", "设施名称", "分类", "地址", "评分", "距起点距离(米)"},
                rows);
    }

    /** 评价状态转文字 */
    private String evalStatus(Integer status) {
        if (status == null) {
            return "";
        }
        return switch (status) {
            case 0 -> "待审核";
            case 1 -> "已通过";
            case 2 -> "已驳回";
            default -> "未知";
        };
    }

    /** 通用：生成 xlsx 并写入响应流 */
    private void writeXlsx(HttpServletResponse response, String filename,
                           String[] headers, Object[][] rows) throws IOException {
        try (XSSFWorkbook wb = new XSSFWorkbook()) {
            Sheet sheet = wb.createSheet(filename.length() > 31 ? filename.substring(0, 31) : filename);
            Row headerRow = sheet.createRow(0);
            for (int i = 0; i < headers.length; i++) {
                headerRow.createCell(i).setCellValue(headers[i]);
            }
            for (int r = 0; r < rows.length; r++) {
                Row row = sheet.createRow(r + 1);
                Object[] data = rows[r];
                for (int c = 0; c < data.length; c++) {
                    Cell cell = row.createCell(c);
                    Object v = data[c];
                    if (v == null) {
                        cell.setCellValue("");
                    } else if (v instanceof Number n) {
                        cell.setCellValue(n.doubleValue());
                    } else {
                        cell.setCellValue(v.toString());
                    }
                }
            }
            for (int i = 0; i < headers.length; i++) {
                sheet.autoSizeColumn(i);
            }

            response.setContentType("application/vnd.openxmlformats-officedocument.spreadsheetml.sheet");
            String encoded = URLEncoder.encode(filename, StandardCharsets.UTF_8).replace("+", "%20");
            response.setHeader("Content-Disposition", "attachment;filename=" + encoded + ".xlsx");
            try (OutputStream os = response.getOutputStream()) {
                wb.write(os);
                os.flush();
            }
        }
    }
}
