package com.doommeeting.server.service;

import com.doommeeting.server.common.BusinessException;
import com.doommeeting.server.config.AppProperties;
import com.doommeeting.server.dto.ChatDtos.ChatMessageResponse;
import com.doommeeting.server.entity.Room;
import com.doommeeting.server.entity.RoomMember;
import com.doommeeting.server.enums.RoomStatus;
import com.doommeeting.server.event.RoomClosedEvent;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.context.event.EventListener;
import org.springframework.core.io.FileSystemResource;
import org.springframework.core.io.Resource;
import org.springframework.http.MediaType;
import org.springframework.stereotype.Service;
import org.springframework.web.multipart.MultipartFile;

import java.io.IOException;
import java.io.InputStream;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.nio.file.StandardCopyOption;
import java.util.ArrayDeque;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.Deque;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import java.util.concurrent.ConcurrentHashMap;
import java.util.regex.Pattern;
import java.util.stream.Stream;

/**
 * 房间聊天: 内存保存近 100 条(文字 + 图片), 通过房间 STOMP 主题实时广播("CHAT" 事件)。
 * 图片文件保存在 app.chat.image-dir/房间号/ 下, 通过手机端接口按房间号+文件名读取。
 * 房间关闭(结束/重置/删除/到期)时清空该房间记录与图片, 固定房下一场会议不会看到上一场的消息。
 */
@Slf4j
@Service
@RequiredArgsConstructor
public class ChatService {

    private static final int MAX_HISTORY = 100;
    private static final Pattern IMAGE_FILE_NAME = Pattern.compile("^[0-9a-f-]{36}\\.(jpg|png|gif|webp)$");
    private static final Pattern ROOM_CODE = Pattern.compile("^[A-Za-z0-9_-]{1,32}$");
    /** 允许的图片类型 -> 保存扩展名 */
    private static final Map<String, String> IMAGE_EXTENSIONS = Map.of(
            MediaType.IMAGE_JPEG_VALUE, "jpg",
            MediaType.IMAGE_PNG_VALUE, "png",
            MediaType.IMAGE_GIF_VALUE, "gif",
            "image/webp", "webp");

    private final RoomService roomService;
    private final MemberService memberService;
    private final NotificationService notificationService;
    private final AppProperties properties;

    private final Map<String, Deque<ChatMessageResponse>> history = new ConcurrentHashMap<>();

    /** 手机端发送聊天消息(校验成员凭证) */
    public ChatMessageResponse sendFromMember(String roomCode, String identity,
                                              String memberToken, String content) {
        Room room = requireOpenRoom(roomCode);
        RoomMember member = memberService.requireOnlineMember(room, identity, memberToken);
        return append(room.getRoomCode(), ChatMessageResponse.text(newMessageId(),
                member.getNickname(), member.getIdentity(), content.trim(), false));
    }

    /** 手机端发送图片消息: 保存文件后以图片地址广播 */
    public ChatMessageResponse sendImageFromMember(String roomCode, String identity,
                                                   String memberToken, MultipartFile file) {
        Room room = requireOpenRoom(roomCode);
        RoomMember member = memberService.requireOnlineMember(room, identity, memberToken);
        String fileName = storeImage(room.getRoomCode(), file);
        String imageUrl = "/api/mobile/rooms/" + room.getRoomCode() + "/chat/images/" + fileName;
        return append(room.getRoomCode(), ChatMessageResponse.image(newMessageId(),
                member.getNickname(), member.getIdentity(), imageUrl, false));
    }

    /** PC 管理端发送聊天消息 */
    public ChatMessageResponse sendFromAdmin(Long roomId, String operator, String content) {
        Room room = roomService.getRoomById(roomId);
        if (room.getStatus() == RoomStatus.CLOSED) {
            throw new BusinessException("房间已关闭, 无法发送消息");
        }
        return append(room.getRoomCode(),
                ChatMessageResponse.text(newMessageId(), operator, null, content.trim(), true));
    }

    /** 读取聊天图片; 文件名只接受服务端生成的 uuid.扩展名, 防止路径穿越 */
    public Resource loadImage(String roomCode, String fileName) {
        if (!ROOM_CODE.matcher(roomCode).matches() || !IMAGE_FILE_NAME.matcher(fileName).matches()) {
            throw new BusinessException(404, "图片不存在");
        }
        Path path = roomImageDir(roomCode).resolve(fileName).normalize();
        if (!path.startsWith(imageRoot()) || !Files.isRegularFile(path)) {
            throw new BusinessException(404, "图片不存在");
        }
        return new FileSystemResource(path);
    }

    /** 近期聊天记录(时间正序) */
    public List<ChatMessageResponse> recent(String roomCode) {
        Deque<ChatMessageResponse> deque = history.get(roomCode);
        if (deque == null) {
            return List.of();
        }
        synchronized (deque) {
            return new ArrayList<>(deque);
        }
    }

    public List<ChatMessageResponse> recentByRoomId(Long roomId) {
        return recent(roomService.getRoomById(roomId).getRoomCode());
    }

    /** 房间关闭/删除时清理内存聊天记录与图片文件 */
    public void clear(String roomCode) {
        history.remove(roomCode);
        deleteRoomImages(roomCode);
    }

    @EventListener
    public void onRoomClosed(RoomClosedEvent event) {
        clear(event.roomCode());
    }

    private Room requireOpenRoom(String roomCode) {
        Room room = roomService.getRoomByCode(roomCode);
        if (room.getStatus() == RoomStatus.CLOSED) {
            throw new BusinessException("房间已关闭, 无法发送消息");
        }
        return room;
    }

    private String storeImage(String roomCode, MultipartFile file) {
        if (file == null || file.isEmpty()) {
            throw new BusinessException("图片不能为空");
        }
        long maxBytes = (long) properties.getChat().getImageMaxSizeMb() * 1024 * 1024;
        if (file.getSize() > maxBytes) {
            throw new BusinessException("图片不能超过 " + properties.getChat().getImageMaxSizeMb() + "MB");
        }
        String extension = resolveExtension(file);
        String fileName = UUID.randomUUID() + "." + extension;
        try {
            Path dir = roomImageDir(roomCode);
            Files.createDirectories(dir);
            try (InputStream in = file.getInputStream()) {
                Files.copy(in, dir.resolve(fileName), StandardCopyOption.REPLACE_EXISTING);
            }
        } catch (IOException e) {
            log.error("保存聊天图片失败 room={} : {}", roomCode, e.getMessage());
            throw new BusinessException("图片保存失败, 请重试");
        }
        return fileName;
    }

    /** 按 Content-Type 判断图片类型, 缺失时回退到文件名后缀 */
    private static String resolveExtension(MultipartFile file) {
        String contentType = file.getContentType();
        if (contentType != null) {
            String extension = IMAGE_EXTENSIONS.get(contentType.toLowerCase());
            if (extension != null) {
                return extension;
            }
        }
        String original = file.getOriginalFilename();
        if (original != null) {
            String lower = original.toLowerCase();
            if (lower.endsWith(".jpg") || lower.endsWith(".jpeg")) return "jpg";
            if (lower.endsWith(".png")) return "png";
            if (lower.endsWith(".gif")) return "gif";
            if (lower.endsWith(".webp")) return "webp";
        }
        throw new BusinessException("仅支持 JPG/PNG/GIF/WebP 图片");
    }

    private Path imageRoot() {
        return Paths.get(properties.getChat().getImageDir()).toAbsolutePath().normalize();
    }

    private Path roomImageDir(String roomCode) {
        return imageRoot().resolve(roomCode);
    }

    private void deleteRoomImages(String roomCode) {
        Path dir = roomImageDir(roomCode);
        if (!Files.isDirectory(dir)) {
            return;
        }
        try (Stream<Path> paths = Files.walk(dir)) {
            paths.sorted(Comparator.reverseOrder()).forEach(path -> {
                try {
                    Files.deleteIfExists(path);
                } catch (IOException e) {
                    log.warn("删除聊天图片失败 {} : {}", path, e.getMessage());
                }
            });
        } catch (IOException e) {
            log.warn("清理聊天图片目录失败 {} : {}", dir, e.getMessage());
        }
    }

    private static String newMessageId() {
        return UUID.randomUUID().toString();
    }

    private ChatMessageResponse append(String roomCode, ChatMessageResponse message) {
        Deque<ChatMessageResponse> deque =
                history.computeIfAbsent(roomCode, key -> new ArrayDeque<>());
        synchronized (deque) {
            deque.addLast(message);
            while (deque.size() > MAX_HISTORY) {
                deque.removeFirst();
            }
        }
        Map<String, Object> payload = new HashMap<>();
        payload.put("id", message.id());
        payload.put("sender", message.sender());
        if (message.identity() != null) {
            payload.put("identity", message.identity());
        }
        payload.put("content", message.content());
        if (message.imageUrl() != null) {
            payload.put("imageUrl", message.imageUrl());
        }
        payload.put("fromAdmin", message.fromAdmin());
        payload.put("sentAt", String.valueOf(message.sentAt()));
        notificationService.pushToRoomAndAdmin(roomCode, "CHAT", payload);
        return message;
    }
}
