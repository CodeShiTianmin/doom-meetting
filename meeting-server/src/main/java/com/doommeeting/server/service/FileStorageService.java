package com.doommeeting.server.service;

import com.doommeeting.server.common.BusinessException;
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
        String relativePath = UUID.randomUUID().toString().replace("-", "") + "_" + safeName;
        try {
            Files.copy(file.getInputStream(), rootDir.resolve(relativePath),
                    StandardCopyOption.REPLACE_EXISTING);
        } catch (IOException e) {
            throw new BusinessException("文件保存失败: " + e.getMessage());
        }
        return relativePath;
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

    /** 删除存储文件(会议结束清理), 失败不抛异常 */
    public void delete(String relativePath) {
        if (relativePath == null || relativePath.isBlank()) {
            return;
        }
        try {
            Path path = rootDir.resolve(relativePath).normalize();
            if (path.startsWith(rootDir)) {
                Files.deleteIfExists(path);
            }
        } catch (IOException ignored) {
        }
    }
}
