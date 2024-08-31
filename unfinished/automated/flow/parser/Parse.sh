#!/usr/bin/env bash
yqFile=
confFile=
basePath=
javaCommand=
gapSecond=
retryTime=
workPath=
cdCommand=

GetAndCheckParserAndYamlFile(){
    # 检测解析器和配置文件存在性，没问题就供后续调用
    case $(uname -m) in
    "aarch64")
        yqFile="./flow/parser/yq_linux_arm64"
    ;;
    "x86_64")
        yqFile="./flow/parser/yq_linux_amd64"
    ;;
    esac

    if [ ! -f "${yqFile}" ]; then
        formatError "解析器不存在，退出中"
        exit 1
    elif [ ! -x "${yqFile}" ]; then
        chmod +x "${yqFile}"
    elif ! ${yqFile} -h >/dev/null 2>&1; then
        formatError "程序无法运行，请检查程序是否在当前CPU架构下可用？"
        formatErrorNoBlank "解析器信息："
        file "${yqFile}"
        formatErrorNoBlank "本机CPU架构："
        uname -m
        formatError "退出中"
        exit 1
    fi

    if [ ! -f ./config.yml ] && [ ! -f ./config.yaml ]; then
        cp -p ./flow/parser/demo.yml ./config.yml
        formatError "配置文件不存在，已创建配置文件示例如下路径："
        formatPrint "${entryPath}/config.yml"
        formatError "请联系开发人员根据实际需求修改配置文件并重新运行mc命令，退出中"
        exit 1
    elif [ -f ./config.yml ]; then
        confFile="./config.yml"
    elif [ -f ./config.yaml ]; then
        confFile="./config.yaml"
    fi

}

ParseGroup(){
    # 先确认yml文件从整体上可以被正常解析
    if ! ${yqFile} '.' "${confFile}" 1>/dev/null; then
        formatError "配置文件出现异常，已输出报错信息，退出中"
        exit 1
    fi
    # 先确定排除组
    if ! ${yqFile} '.group[]|key' "${confFile}" | grep -o '^exclude$' >/dev/null; then
        formatError "排除列表（group.exclude）哪怕是空的都必须存在，请修改配置文件，退出中"
        exit 1
    fi

    case $(${yqFile} '.group.exclude | tag' "${confFile}") in
    "!!seq")
        excludeServiceList+=("排除组")
        mapfile -t -O "${#excludeServiceList[@]}" excludeServiceList < <(${yqFile} '.group.exclude[]' "${confFile}")
        ;;
    "!!null")
        excludeServiceList+=("排除组")
        ;;
    *)
        formatError "排除列表对象（group.exclude）的参数支持格式如下："
        formatErrorNoBlank "1. 不填写参数" \
        "2. 参数为空数组写法：[]" \
        "3. 参数为 yaml 的数组写法（列表）" \
        "4. 参数为 yaml 的行内表示法：[aa, bb, cc]" \
        "请检查，退出中"
        exit 1
    esac

    # 获取服务组名列表，筛掉其中未启用的所有组名(包括member列表为空的组名)
    # 同时删除已启用组中已经放进exclude组的服务名
    local groupIndex
    mapfile -t groupNameList < <(${yqFile} '.group[]|key' "${confFile}" | grep -v '^exclude$')

    for groupIndex in "${!groupNameList[@]}"; do
        local isEnabled  tempGroupMemberList=()
        isEnabled=$(${yqFile} ".group.${groupNameList[${groupIndex}]}.enable" "${confFile}")
        case ${isEnabled} in
        "yes"|1|"true")
            case $(${yqFile} ".group.${groupNameList[${groupIndex}]}.member | tag" "${confFile}") in
            "!!seq")
                mapfile -t -O "${#tempGroupMemberList[@]}" tempGroupMemberList < <(${yqFile} ".group.${groupNameList[${groupIndex}]}.member[]" "${confFile}")
                if [ "${#tempGroupMemberList[@]}" -eq 0 ]; then
                    unset "groupNameList[${groupIndex}]"
                    continue
                fi
                local invalidService tempIndex
                for invalidService in "${excludeServiceList[@]}" ; do
                    for tempIndex in "${!tempGroupMemberList[@]}" ; do
                        if [ "${tempGroupMemberList[${tempIndex}]}" == "${invalidService}" ]; then
                            unset "tempGroupMemberList[${tempIndex}]"
                            continue
                        fi
                    done
                done
                unset invalidService tempIndex
                local groupElementFirstIndex groupElementLastIndex
                mapfile -t -O "${#groupAndServiceChain[@]}" groupAndServiceChain < <(echo "${groupNameList[${groupIndex}]}组")
                groupElementFirstIndex="${#groupAndServiceChain[@]}"
                groupAndServiceChain=("${groupAndServiceChain[@]}" "${tempGroupMemberList[@]}")
                groupElementLastIndex=$((${#groupAndServiceChain[@]} - 1))
                groupAndServiceIndexPair["${groupNameList[${groupIndex}]}"]="${groupElementFirstIndex}:${groupElementLastIndex}"

                allServiceList=("${allServiceList[@]}" "${tempGroupMemberList[@]}")
                unset groupElementFirstIndex groupElementLastIndex tempGroupMemberList
                ;;
            "!!null")
                unset "groupNameList[${groupIndex}]"
                continue
                ;;
            *)
                formatError "${groupNameList[${groupIndex}]}组中的成员对象（service.${groupNameList[${groupIndex}]}.member）的参数支持格式如下："
                formatErrorNoBlank "1. 不填写参数" \
                "2. 参数为空数组写法：[]" \
                "3. 参数为 yaml 的数组写法（列表）" \
                "4. 参数为 yaml 的行内表示法：[aa, bb, cc]" \
                "请检查，退出中"
                exit 1
            esac
        ;;
        "no"|0|"false")
            unset "groupNameList[${groupIndex}]"
        ;;
        *)
            formatError "组启用策略值设置错误，启用的值为：yes 或 1，停用的值为：no 或 0，退出中"
            exit 1
        esac
        unset isEnabled
    done

#    # 测试数组组装情况
#    for key in "${!groupAndServiceIndexPair[@]}"; do
#        value="${groupAndServiceIndexPair[$key]}"
#        echo "Key: $key, Value: $value"
#    done
}

ParseCommon(){
    # 解析common中的配置
    local addEnv
    addEnv=$(${yqFile} ".common.add-env" "${confFile}")
    if [ -z "${addEnv}" ] || [ "${addEnv}" == "null" ]; then
        :
    else
        case ${addEnv} in
        "yes"|1|"true")
            if [ ! -f /usr/bin/mc ] || [ ! -L /usr/bin/mc ]; then
                ln -s "${mcPath}" /usr/bin/mc
                formatSuccess "已将工具启动入口添加到系统环境变量中，以后可直接在命令行中执行命令 mc 即可"
            fi
            ;;
        "no"|0|"false")
            if [ -f /usr/bin/mc ] || [ -L /usr/bin/mc ]; then
                rm -rf /usr/bin/mc
                formatSuccess "已将工具启动入口从系统环境变量中移除"
            fi
            ;;
        *)
            formatError "common.add-env选项值设置错误，true或1或yes为添加，false或0或no为不添加"
            formatError "请检查，退出中"
            exit 1
        esac
    fi

    workPath=$(${yqFile} ".common.work-path" "${confFile}")
    if [ -z "${workPath}" ] || [ "${workPath}" == "null" ]; then
        cdCommand=""
    elif ! workPath=$(grep -o '^/.*' <<< "${workPath}"); then
        formatError "存放日志的根路径禁止使用相对路径，请修改，退出中"
        exit 1
    else
        workPath=$(readlink -f "${workPath}")
        workPath=${workPath%/}
        if [ ! -d "${workPath}" ]; then
            formatWarning "指定的工作目录不存在，启动微服务前将自动创建"
        fi
        cdCommand="cd ${workPath}"
    fi

    basePath=$(${yqFile} ".common.service-base-path" "${confFile}")
    if [ -z "${basePath}" ]; then
        :
    elif ! basePath=$(grep -o '^/.*' <<< "${basePath}"); then
        formatError "存放jar包的根路径禁止使用相对路径，请修改，退出中"
        exit 1
    elif [[ ! -d ${basePath} ]]; then
        formatError "存放jar包的根路径不存在，请检查，退出中"
        exit 1
    else
        basePath=$(readlink -f "${basePath}")
        basePath=${basePath%/}
    fi

    local javaHome
    javaHome=$(${yqFile} ".common.java-home" "${confFile}")
    if [ -z "${javaHome}" ]; then
        formatError "java程序路径必须指定，支持两种写法：" \
        "1. 无需指定版本的java，执行java命令可以直接运行，则填写 java 字样" \
        "2. 填写JAVA_HOME的绝对路径，例：java程序绝对路径是/a/b/c/jdk/bin/java，则JAVA_HOME=/a/b/c/jdk" \
        "请修改，退出中"
        exit 1
    fi

    if [ "${javaHome}" == "java" ]; then
        if ! which java > /dev/null; then
            formatError "当前系统并没有安装java，请检查，退出中"
            exit 1
        fi
        javaCommand=$(readlink -f "$(which java)")
    else
        if ! grep -o '^/.*' <<< "${javaHome}"; then
            formatError "JAVA_HOME路径必须是绝对路径，请修改，退出中"
            exit 1
        fi
        if [ ! -f "${javaHome%/}/bin/java" ]; then
            formatError "指定的JAVA_HOME绝对路径下找不到java程序，请检查，退出中"
            exit 1
        fi
        javaCommand=$(readlink -f "${javaHome%/}/bin/java")
    fi

    gapSecond=$(${yqFile} ".common.retry.gap-second" "${confFile}")
    if [ -z "${gapSecond}" ]; then
        formatError "终止进程操作和检测进程存活操作之间的时间间隔不能为空，请填写间隔秒数，退出中"
        exit 1
    elif [ "${gapSecond}" == "null" ]; then
        formatError "终止进程操作和检测进程存活操作之间的时间间隔的配置丢失，请检查，退出中"
        exit 1
    fi

    retryTime=$(${yqFile} ".common.retry.retry-time" "${confFile}")
    if [ -z "${retryTime}" ]; then
        formatError "进程终止失败后的重试次数不能为空，请填写重试次数，退出中"
        exit 1
    elif [ "${retryTime}" == "null" ]; then
        formatError "进程终止失败后的重试次数的配置丢失，请检查，退出中"
        exit 1
    fi
}

# 此函数目的是在不影响现有最小化功能的基础上，引入外挂的定制启动命令模块，由于此项目功能基于数组操作，所以需要将定制的服务从默认数组中提取出来
AdjustArray(){
    #-----------------------------------------------------------------------------------------------------------------------
    # rebuildServiceList
    local tempRebuildServiceList=() i0 e0
    declare -gA rebuildServiceList
    # 从解析出来的重建列表中删掉exclude列表中存在的服务名
    case $(${yqFile} '.set.rebuild | tag' "${confFile}") in
    "!!seq")
        mapfile -t -O "${#tempRebuildServiceList[@]}" tempRebuildServiceList < <(${yqFile} '.set.rebuild[]' "${confFile}")
        for i0 in "${!tempRebuildServiceList[@]}" ; do
            for e0 in "${excludeServiceList[@]}"; do
                if [[ ${e0} == "${tempRebuildServiceList[${i0}]}" ]]; then
                    unset "tempRebuildServiceList[${e0}]"
                    break
                fi
            done
            rebuildServiceList["${tempRebuildServiceList[${i0}]}"]=1
        done
        ;;
    "!!null")
        return
        ;;
    *)
        formatError "重建列表对象（set.rebuild）的参数支持格式如下："
        formatErrorNoBlank "1. 不填写参数" \
        "2. 参数为空数组写法：[]" \
        "3. 参数为 yaml 的数组写法（列表）" \
        "4. 参数为 yaml 的行内表示法：[aa, bb, cc]" \
        "请检查，退出中"
        exit 1
    esac

    local e1
    for e1 in "${allServiceList[@]}"; do
        if [[ ${rebuildServiceList["${e2}"]} == 1 ]]; then
            :
        fi
        break
    done
    local invalidService tempIndex
    for invalidService in "${excludeServiceList[@]}" ; do
        for tempIndex in "${!tempGroupMemberList[@]}" ; do
            if [ "${tempGroupMemberList[${tempIndex}]}" == "${invalidService}" ]; then
                unset "tempGroupMemberList[${tempIndex}]"
                continue
            fi
        done
    done
    unset invalidService tempIndex
    local groupElementFirstIndex groupElementLastIndex
    mapfile -t -O "${#groupAndServiceChain[@]}" groupAndServiceChain < <(echo "${groupNameList[${groupIndex}]}组")
    groupElementFirstIndex="${#groupAndServiceChain[@]}"
    groupAndServiceChain=("${groupAndServiceChain[@]}" "${tempGroupMemberList[@]}")
    groupElementLastIndex=$((${#groupAndServiceChain[@]} - 1))
    groupAndServiceIndexPair["${groupNameList[${groupIndex}]}"]="${groupElementFirstIndex}:${groupElementLastIndex}"

    allServiceList=("${allServiceList[@]}" "${tempGroupMemberList[@]}")
    unset groupElementFirstIndex groupElementLastIndex tempGroupMemberList
    #-----------------------------------------------------------------------------------------------------------------------
}

ParseService(){
    # 检查groupAndServiceChain中的所有已启用服务均在service节点中有对应的配置节点。
    local serviceList=() flag availableService service
    mapfile -t serviceList < <(${yqFile} '.service[]|key' "${confFile}")
    for availableService in "${groupAndServiceChain[@]}"; do
        flag=0
        if [[ "${availableService}" =~ "组" ]]; then
            continue
        fi
        for service in "${serviceList[@]}"; do
            if [ "${service}" == "${availableService}" ]; then
                flag=0
                break
            fi
            flag=1
        done
        if [ "${flag}" -eq 1 ]; then
            formatError "${availableService}服务在配置文件的service节点下找不到对应的具体配置，请检查，退出中"
            exit 1
        fi
    done
    unset serviceList flag availableService service

    local tempService jarPath jarAbsolutePath javaArgs=() finalCommand serviceFlag
    for tempService in "${groupAndServiceChain[@]}"; do
        if [[ "${tempService}" =~ "组" ]]; then
            continue
        fi

        if [ -z "${basePath}" ]; then
            if ! jarAbsolutePath=$(${yqFile} ".service.${tempService}.jar-path" "${confFile}" | grep -o '^/.*'); then
                formatError "jar包路径必须是绝对路径，请检查，退出中"
                exit 1
            fi
        else
            jarPath=$(${yqFile} ".service.${tempService}.jar-path" "${confFile}")
            jarPath=${jarPath#/}
            jarAbsolutePath="${basePath}/${jarPath}"
        fi
        if [ ! -f "${jarAbsolutePath}" ]; then
            formatError "不存在此文件：${jarAbsolutePath}" "请检查，退出中"
            exit 1
        fi

        case $(${yqFile} ".service.${tempService}.java-args | tag" "${confFile}") in
            "!!seq")
                mapfile -t javaArgs < <(${yqFile} ".service.${tempService}.java-args[]" "${confFile}")
                ;;
            "!!null")
                javaArgs=()
                ;;
            *)
                formatError "排除列表对象（service.${tempService}.java-args）的参数支持格式如下："
                formatErrorNoBlank "1. 不填写参数" \
                "2. 参数为空数组写法：[]" \
                "3. 参数为 yaml 的数组写法（列表）" \
                "4. 参数为 yaml 的行内表示法：[aa, bb, cc]" \
                "请检查，退出中"
                exit 1
        esac

        serviceFlag="-DmcService=${tempService}"
        finalCommand="nohup ${javaCommand} ${serviceFlag} ${javaArgs[*]} -jar ${jarAbsolutePath}"
        serviceAndCommandPair["${tempService}"]="${finalCommand}"
    done
    unset tempService jarPath jarAbsolutePath javaArgs finalCommand serviceFlag
}

# 此处解析得到的一切参数配置一定不能出错，后面所有逻辑均假定此处得到了绝对正确的配置信息。
formatInfo "正在解析配置文件"
if
GetAndCheckParserAndYamlFile
ParseGroup
ParseCommon
AdjustArray
ParseService; then
    formatSuccess "配置文件解析完成"
fi
