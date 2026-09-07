local mp = require 'mp'
local utils = require 'mp.utils'

local GRID_COLUMNS = 5
local GRID_ROWS = 4
local GRID_GAP = 5

-- 缩略图高度
local THUMB_HEIGHT = 320

local TARGET_FONT_SIZE = 22
local TARGET_BORDER_W = 3

local FFMPEG = "ffmpeg"


--------------------------------------------------
-- Header 设置
--------------------------------------------------

-- 标题字体大小
local HEADER_TITLE_SIZE = 32

-- 信息字体大小
local HEADER_INFO_SIZE = 20

-- Header 顶部边距
local HEADER_TOP_MARGIN = 24

-- Header 左侧边距
local HEADER_LEFT_MARGIN = 16

-- 信息行间距
local HEADER_LINE_SPACING = 5

-- Header 底部边距
local HEADER_BOTTOM_MARGIN = 7


-- mp.msg.info("Contact Sheet script loaded ")
-- mp.msg.info("THUMB_HEIGHT = " .. THUMB_HEIGHT)


--------------------------------------------------
-- 工具函数
--------------------------------------------------

local function format_filesize(bytes)
    if not bytes then
        return "Unknown"
    end

    if bytes >= 1024 * 1024 * 1024 then
        return string.format("%.2f GiB", bytes / (1024 * 1024 * 1024))
    elseif bytes >= 1024 * 1024 then
        return string.format("%.2f MiB", bytes / (1024 * 1024))
    elseif bytes >= 1024 then
        return string.format("%.2f KiB", bytes / 1024)
    else
        return string.format("%d B", bytes)
    end
end


local function format_duration(seconds)
    if not seconds then
        return "Unknown"
    end

    seconds = math.floor(seconds)

    local hours = math.floor(seconds / 3600)
    local minutes = math.floor((seconds % 3600) / 60)
    local secs = seconds % 60

    if hours > 0 then
        return string.format("%02d:%02d:%02d", hours, minutes, secs)
    else
        return string.format("%02d:%02d", minutes, secs)
    end
end


--------------------------------------------------
-- FFmpeg drawtext 字符转义
--------------------------------------------------

local function escape_drawtext(text)
    text = tostring(text)

    -- 反斜杠
    text = text:gsub("\\", "\\\\")

    -- 冒号
    text = text:gsub(":", "\\:")

    -- 单引号
    text = text:gsub("'", "\\'")

    return text
end


--------------------------------------------------
-- 计算采样时间
--------------------------------------------------

local function calculate_sample_times(duration)

    local sample_count = GRID_COLUMNS * GRID_ROWS

    local interval = duration / sample_count

    local times = {}

    for i = 1, sample_count do

        local time =
            (i - 0.5) * interval

        table.insert(
            times,
            time
        )
    end

    return times
end


--------------------------------------------------
-- 获取视频信息
--------------------------------------------------

local function get_video_info()

    local path = mp.get_property("path")

    if not path then
        return nil
    end

    local filename =
        path:match("[^/\\]+$")

    local file_info =
        utils.file_info(path)

    return {

        path = path,

        filename = filename,

        filesize =
            file_info and file_info.size or nil,

        width =
            mp.get_property_number("width"),

        height =
            mp.get_property_number("height"),

        duration =
            mp.get_property_number("duration")
    }
end


--------------------------------------------------
-- 核心功能
--------------------------------------------------

local function create_contact_sheet()

    local video =
        get_video_info()

    if not video then

        mp.osd_message(
            "Contact Sheet: No video loaded",
            3
        )

        return
    end


    if not video.duration then

        mp.osd_message(
            "Contact Sheet: Duration unavailable",
            3
        )

        return
    end


    if not video.width or not video.height then

        mp.osd_message(
            "Contact Sheet: Resolution unavailable",
            3
        )

        return
    end


    --------------------------------------------------
    -- 采样时间
    --------------------------------------------------

    local sample_times =
        calculate_sample_times(
            video.duration
        )


    --------------------------------------------------
    -- 计算缩略图尺寸
    --------------------------------------------------

    local thumb_height =
        THUMB_HEIGHT

    local thumb_width =
        math.floor(
            video.width /
            video.height *
            thumb_height
        )


    --------------------------------------------------
    -- 根据原始视频分辨率反推字幕大小
    --------------------------------------------------

    local scale_factor =
        video.height /
        thumb_height

    local fontsize =
        math.floor(
            TARGET_FONT_SIZE *
            scale_factor
        )

    local borderw =
        math.max(
            2,
            math.floor(
                TARGET_BORDER_W *
                scale_factor
            )
        )

    local text_y_offset =
        math.floor(
            fontsize * 0.4
        )


    --------------------------------------------------
    -- Grid 尺寸
    --------------------------------------------------

    local grid_width =
        GRID_COLUMNS * thumb_width +
        (GRID_COLUMNS - 1) * GRID_GAP

    local grid_height =
        GRID_ROWS * thumb_height +
        (GRID_ROWS - 1) * GRID_GAP


    --------------------------------------------------
    -- Header 尺寸
    --------------------------------------------------

    local header_height =
        HEADER_TOP_MARGIN +
        HEADER_TITLE_SIZE +
        (HEADER_INFO_SIZE * 4) +
        (HEADER_LINE_SPACING * 4) +
        HEADER_BOTTOM_MARGIN


    --------------------------------------------------
    -- 最终图片尺寸
    --------------------------------------------------

    local final_width =
        grid_width

    local final_height =
        header_height +
        grid_height


    --------------------------------------------------
    -- 屏幕显示确认参数
    --------------------------------------------------

    local osd_msg =
        string.format(
            "Contact Sheet\n" ..
            "THUMB_HEIGHT: %d\n" ..
            "Thumb: %dx%d\n" ..
            "Header: %dx%d\n" ..
            "Grid: %dx%d\n" ..
            "Final: %dx%d\n" ..
            "Font: %d",

            THUMB_HEIGHT,

            thumb_width,
            thumb_height,

            final_width,
            header_height,

            grid_width,
            grid_height,

            final_width,
            final_height,

            fontsize
        )


    mp.osd_message(
        osd_msg,
        5
    )

    mp.msg.info(
        osd_msg
    )


    --------------------------------------------------
    -- 临时文件
    --------------------------------------------------

    local temp_files = {}


    --------------------------------------------------
    -- 第一阶段：提取 20 帧
    --------------------------------------------------

    mp.msg.info(
        "=== Phase 1: Extracting frames ==="
    )


    for i, sample_time in ipairs(sample_times) do

        local timestamp =
            format_duration(
                sample_time
            )

        local drawtext_timestamp =
            escape_drawtext(
                timestamp
            )


        mp.msg.info(
            string.format(
                "Frame %d/%d at %s",
                i,
                #sample_times,
                timestamp
            )
        )


        --------------------------------------------------
        -- 中间文件使用 PNG
        --------------------------------------------------

        local output =
            video.path ..
            string.format(
                ".cs-temp-%02d.png",
                i
            )


        table.insert(
            temp_files,
            output
        )


        --------------------------------------------------
        -- Frame 时间戳
        --------------------------------------------------

        local vf_string =

            "drawtext=" ..

            "fontfile='C\\:/Windows/Fonts/arial.ttf':" ..

            "text='" ..
            drawtext_timestamp ..
            "':" ..

            "fontcolor=white:" ..

            "fontsize=" ..
            tostring(fontsize) ..
            ":" ..

            "borderw=" ..
            tostring(borderw) ..
            ":" ..

            "bordercolor=black:" ..

            "x=(w-text_w)/2:" ..

            "y=h-text_h-" ..
            tostring(text_y_offset)


        --------------------------------------------------
        -- FFmpeg 提取
        --------------------------------------------------

        local result =
            mp.command_native({

                name = "subprocess",

                args = {

                    FFMPEG,

                    "-y",

                    "-ss",
                    tostring(sample_time),

                    "-i",
                    video.path,

                    "-vf",
                    vf_string,

                    "-frames:v",
                    "1",

                    output
                },

                playback_only = false,

                capture_stdout = true,

                capture_stderr = true
            })


        if result.status ~= 0 then

            mp.msg.error(
                "FFmpeg failed for frame " ..
                i
            )

            if result.stderr then

                mp.msg.error(
                    result.stderr
                )
            end
        end
    end


    mp.msg.info(
        "=== Phase 2: Merging ==="
    )


    --------------------------------------------------
    -- 第二阶段
    -- Grid + Header
    --------------------------------------------------

    local output =
        video.path ..
        ".contact-sheet.png"


    local args = {
        FFMPEG,
        "-y"
    }


    --------------------------------------------------
    -- 加入 20 个 PNG
    --------------------------------------------------

    for i = 1, #sample_times do

        local input =
            video.path ..
            string.format(
                ".cs-temp-%02d.png",
                i
            )

        table.insert(
            args,
            "-i"
        )

        table.insert(
            args,
            input
        )
    end


    --------------------------------------------------
    -- Grid 缩放
    --------------------------------------------------

    local filters = {}


    for i = 0, #sample_times - 1 do

        table.insert(
            filters,

            string.format(
                "[%d:v]scale=%d:%d[v%d]",
                i,
                thumb_width,
                thumb_height,
                i
            )
        )
    end


    --------------------------------------------------
    -- Grid 位置
    --------------------------------------------------

    local layout_positions = {}


    for row = 0, GRID_ROWS - 1 do

        for col = 0, GRID_COLUMNS - 1 do

            local x =
                col *
                (thumb_width + GRID_GAP)

            local y =
                row *
                (thumb_height + GRID_GAP)


            table.insert(
                layout_positions,

                string.format(
                    "%d_%d",
                    x,
                    y
                )
            )
        end
    end


    local layout =
        table.concat(
            layout_positions,
            "|"
        )


    --------------------------------------------------
    -- Grid 输入
    --------------------------------------------------

    local inputs = {}


    for i = 0, #sample_times - 1 do

        table.insert(
            inputs,

            string.format(
                "[v%d]",
                i
            )
        )
    end


    --------------------------------------------------
    -- Grid xstack
    --------------------------------------------------

    local grid_filter =

        table.concat(
            filters,
            ";"
        ) ..

        ";" ..

        table.concat(
            inputs,
            ""
        ) ..

        string.format(
            "xstack=inputs=%d:layout=%s:fill=black",
            #sample_times,
            layout
        ) ..

        "[xstack_out]"


    --------------------------------------------------
    -- Header 文本
    --
    -- 注意：
    -- 这里整行一起 escape_drawtext
    -- 因此 File Name: 中的冒号也会被正确转义
    --------------------------------------------------

    local filename =
        escape_drawtext(
            "File Name: " ..
            tostring(
                video.filename
            )
        )


    local filesize =
        escape_drawtext(
            "File Size: " ..
            format_filesize(
                video.filesize
            )
        )


    local resolution =
        escape_drawtext(
            "Resolution: " ..
            tostring(
                video.width
            ) ..
            "x" ..
            tostring(
                video.height
            )
        )


    local duration =
        escape_drawtext(
            "Duration: " ..
            format_duration(
                video.duration
            )
        )


    --------------------------------------------------
    -- Header
    --------------------------------------------------

    local title_y =
        HEADER_TOP_MARGIN


    local info1_y =
        title_y +
        HEADER_TITLE_SIZE +
        HEADER_LINE_SPACING


    local info2_y =
        info1_y +
        HEADER_INFO_SIZE +
        HEADER_LINE_SPACING


    local info3_y =
        info2_y +
        HEADER_INFO_SIZE +
        HEADER_LINE_SPACING


    local info4_y =
        info3_y +
        HEADER_INFO_SIZE +
        HEADER_LINE_SPACING


    --------------------------------------------------
    -- Header 黑色画布 + 文字
    --------------------------------------------------

    local header_filter =

        "color=" ..

        "c=black:" ..

        "s=" ..
        tostring(final_width) ..
        "x" ..
        tostring(header_height) ..

        ":d=1" ..

        "[header_base];"


    --------------------------------------------------
    -- 标题
    --------------------------------------------------

    header_filter =

        header_filter ..

        "[header_base]" ..

        "drawtext=" ..

        "fontfile='C\\:/Windows/Fonts/arialbd.ttf':" ..

        "text='mpv Media Player':" ..

        "fontcolor=white:" ..

        "fontsize=" ..
        tostring(HEADER_TITLE_SIZE) ..

        ":" ..

        "x=" ..
        tostring(HEADER_LEFT_MARGIN) ..

        ":" ..

        "y=" ..
        tostring(title_y) ..

        "[header_title];"


    --------------------------------------------------
    -- File Name
    --------------------------------------------------

    header_filter =

        header_filter ..

        "[header_title]" ..

        "drawtext=" ..

        "fontfile='C\\:/Windows/Fonts/msyh.ttc':" ..

        "text='" ..
        filename ..
        "':" ..

        "fontcolor=white:" ..

        "fontsize=" ..
        tostring(HEADER_INFO_SIZE) ..

        ":" ..

        "x=" ..
        tostring(HEADER_LEFT_MARGIN) ..

        ":" ..

        "y=" ..
        tostring(info1_y) ..

        "[header_filename];"


    --------------------------------------------------
    -- File Size
    --------------------------------------------------

    header_filter =

        header_filter ..

        "[header_filename]" ..

        "drawtext=" ..

        "fontfile='C\\:/Windows/Fonts/msyh.ttc':" ..

        "text='" ..
        filesize ..
        "':" ..

        "fontcolor=white:" ..

        "fontsize=" ..
        tostring(HEADER_INFO_SIZE) ..

        ":" ..

        "x=" ..
        tostring(HEADER_LEFT_MARGIN) ..

        ":" ..

        "y=" ..
        tostring(info2_y) ..

        "[header_filesize];"


    --------------------------------------------------
    -- Resolution
    --------------------------------------------------

    header_filter =

        header_filter ..

        "[header_filesize]" ..

        "drawtext=" ..

        "fontfile='C\\:/Windows/Fonts/msyh.ttc':" ..

        "text='" ..
        resolution ..
        "':" ..

        "fontcolor=white:" ..

        "fontsize=" ..
        tostring(HEADER_INFO_SIZE) ..

        ":" ..

        "x=" ..
        tostring(HEADER_LEFT_MARGIN) ..

        ":" ..

        "y=" ..
        tostring(info3_y) ..

        "[header_resolution];"


    --------------------------------------------------
    -- Duration
    --------------------------------------------------

    header_filter =

        header_filter ..

        "[header_resolution]" ..

        "drawtext=" ..

        "fontfile='C\\:/Windows/Fonts/msyh.ttc':" ..

        "text='" ..
        duration ..
        "':" ..

        "fontcolor=white:" ..

        "fontsize=" ..
        tostring(HEADER_INFO_SIZE) ..

        ":" ..

        "x=" ..
        tostring(HEADER_LEFT_MARGIN) ..

        ":" ..

        "y=" ..
        tostring(info4_y) ..

        "[header];"


    --------------------------------------------------
    -- 最终 Filter
    --
    -- Header
    --      ↓
    -- Grid
    --      ↓
    -- 上下拼接
    --------------------------------------------------

    local filter_complex =

        table.concat(
            filters,
            ";"
        ) ..

        ";" ..

        table.concat(
            inputs,
            ""
        ) ..

        string.format(
            "xstack=inputs=%d:layout=%s:fill=black",
            #sample_times,
            layout
        ) ..

        "[xstack_out];" ..

        header_filter ..

        "[header][xstack_out]" ..

        "vstack=inputs=2[out]"


    --------------------------------------------------
    -- FFmpeg 参数
    --------------------------------------------------

    table.insert(
        args,
        "-filter_complex"
    )

    table.insert(
        args,
        filter_complex
    )


    table.insert(
        args,
        "-map"
    )

    table.insert(
        args,
        "[out]"
    )


    table.insert(
        args,
        "-frames:v"
    )

    table.insert(
        args,
        "1"
    )


    --------------------------------------------------
    -- 输出 PNG
    --------------------------------------------------

    table.insert(
        args,
        output
    )


    --------------------------------------------------
    -- 执行 FFmpeg
    --------------------------------------------------

    local result =
        mp.command_native({

            name = "subprocess",

            args = args,

            playback_only = false,

            capture_stdout = true,

            capture_stderr = true
        })


    --------------------------------------------------
    -- 判断结果
    --------------------------------------------------

    if result.status == 0 then

        local file_info =
            utils.file_info(
                output
            )


        local size_str =
            file_info and
            format_filesize(
                file_info.size
            ) or
            "Unknown"


        mp.msg.info(
            "SUCCESS: " ..
            output ..
            " (" ..
            size_str ..
            ")"
        )


        mp.osd_message(

            "Contact Sheet created!\n" ..

            final_width ..
            "x" ..
            final_height ..

            "\n" ..

            size_str,

            5
        )

    else

        mp.msg.error(
            "FAILED to create contact sheet"
        )


        if result.stderr then

            mp.msg.error(
                result.stderr
            )
        end


        mp.osd_message(
            "Contact Sheet FAILED",
            5
        )
    end


    --------------------------------------------------
    -- 删除临时文件
    --------------------------------------------------

    for _, f in ipairs(temp_files) do

        os.remove(f)

    end


    mp.msg.info(
        "Temp files cleaned"
    )
end


--------------------------------------------------
-- 快捷键
--------------------------------------------------

mp.add_key_binding(
    "c",
    "contact-sheet-create",
    create_contact_sheet
)