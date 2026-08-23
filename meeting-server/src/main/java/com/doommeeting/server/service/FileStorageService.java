package com.doommeeting.server.service;

import com.doommeeting.server.common.BusinessException;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.core.io.Resource;
import org.springframework.core.io.UrlResource;
import org.springframework.stereotype.Service;
import org.springframework.web.multipart.MultipartFile;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.nio.file.StandardCopyOption;
import java.util.UUID;

/**
 * 投放文件存储: 上传文件保存到服务器磁盘, 会议结束后由业务层删除
 */
@Slf4j
@Service
public class FileStorageService {

    private final Path rootDir;

    public FileStorageService(@Value("${app.storage.dir:./data/uploads}") String storageDir) {
        this.rootDir = Paths.get(storageDir).toAbsolutePath().normalize();
        try {
            Files.createDirectories(rootDir);
        } catch (IOException e) {
            throw new IllegalStateException("无法创建文件存储目录: " + rootDir, e);
        }
    }

    /** 保存上传文件, 返回存储相对路径 */
    public String store(MultipartFile file) {
        String original = file.getOriginalFilename() == null ? "file" : file.getOriginalFilename();
        String safeName = Paths.get(original).getFileName().toString().replaceAll("[\\\\/:*?\"<>|]", "_");
        safeName = truncateFileName(safeName, 128);
        String relativePath = UUID.randomUUID().toString().replace("-", "") + "_" + safeName;
        Path target = rootDir.resolve(relativePath);
        try {
            Files.copy(file.getInputStream(), target, StandardCopyOption.REPLACE_EXISTING);
        } catch (IOException e) {
            // 清理可能残留的半个文件
            try {
                Files.deleteIfExists(target);
            } catch (IOException cleanupError) {
                log.warn("清理残留文件失败: {}", target, cleanupError);
            }
            throw new BusinessException("文件保存失败: " + e.getMessage());
        }
        return relativePath;
    }

    /** 截断过长文件名(保留扩展名), 避免超出文件系统文件名长度限制 */
    private String truncateFileName(String name, int maxLength) {
        if (name.length() <= maxLength) {
            return name;
        }
        int dot = name.lastIndexOf('.');
        String ext = dot > 0 ? name.substring(dot) : "";
        if (ext.length() >= maxLength) {
            return name.substring(0, maxLength);
        }
        return name.substring(0, maxLength - ext.length()) + ext;
    }

    public Resource loadAsResource(String relativePath) {
        try {
            Path path = rootDir.resolve(relativePath).normalize();
            if (!path.startsWith(rootDir)) {
                throw new BusinessException(404, "文件不存在");
            }
            Resource resource = new UrlResource(path.toUri());
            if (!resource.exists() || !resource.isReadable()) {
                throw new BusinessException(404, "文件不存在或已删除");
            }
            return resource;
        } catch (IOException e) {
            throw new BusinessException(404, "文件不存在");
        }
    }

    /** 删除存储文件(会议结束清理), 失败记录日志不抛异常 */
    public void delete(String relativePath) {
        if (relativePath == null || relativePath.isBlank()) {
            return;
        }
        try {
            Path path = rootDir.resolve(relativePath).normalize();
            if (path.startsWith(rootDir)) {
                Files.deleteIfExists(path);
            }
        } catch (IOException e) {
            log.warn("删除存储文件失败(磁盘残留): {}", relativePath, e);
        }
    }
}
