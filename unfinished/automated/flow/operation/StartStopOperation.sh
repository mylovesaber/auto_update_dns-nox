#!/usr/bin/env bash
needOperateServiceList=()
OperateUsingServiceStyle(){
    local inputName serviceName testFlag inputServiceList=("${extraArgs[@]}")
    if [ "${1}" == "all" ]; then
        needOperateServiceList=("${allServiceList[@]}")
    elif [ -z "${1}" ]; then
        for inputName in "${inputServiceList[@]}" ; do
            testFlag=0
            for serviceName in "${allServiceList[@]}" ; do
                if [ "${serviceName}" == "${inputName}" ]; then
                    testFlag=1
                    break
                fi
            done
            if [ "${testFlag}" -eq 0 ]; then
                formatError "配置文件中找不到${inputName}服务的配置信息，请检查，退出中"
                exit 1
            fi
        done
        needOperateServiceList=("${extraArgs[@]}")
    fi
}

OperateUsingGroupStyle(){
    local inputGroup groupName testFlag inputGroupList=("${extraArgs[@]:1}")
    for inputGroup in "${inputGroupList[@]}" ; do
        testFlag=0
        for groupName in "${groupNameList[@]}" ; do
            if [ "${inputGroup}" == "${groupName}" ]; then
                testFlag=1
                break
            fi
        done
        if [ "${testFlag}" -eq 0 ]; then
            formatError "配置文件中找不到${inputGroup}组的配置信息，请检查，退出中"
            exit 1
        fi
    done
    local startIndex indexLength tempServiceList
    for groupName in "${inputGroupList[@]}" ; do
        startIndex=$(cut -d':' -f1 <<< "${groupAndServiceIndexPair[${groupName}]}")
        indexLength=$(( $(cut -d':' -f2 <<< "${groupAndServiceIndexPair[${groupName}]}") + 1 - startIndex ))
        tempServiceList=("${groupAndServiceChain[@]:${startIndex}:${indexLength}}")
        needOperateServiceList=("${needOperateServiceList[@]}" "${tempServiceList[@]}")
    done
}

# 两种启动方式的公用方法
StartService(){
    formatInfo "开始批量调起指定的所有服务"
    local commandArray serviceName
    if [ ! -d "${workPath}" ]; then
        mkdir -p "${workPath}"
    fi
    for serviceName in "${needOperateServiceList[@]}" ; do
        # 这里mcService=必不可少，否则会因输入的参数和serviceName同名导致永远都跳过
        if pgrep -f "mcService=${serviceName}" >/dev/null 2>&1; then
            formatWarning "${serviceName}服务已启动，跳过"
            continue
        fi
        IFS=' ' read -r -a commandArray <<< "${serviceAndCommandPair[${serviceName}]}"
        # 这里cd命令必须从commandArray独立出来，否则if判断的是cd命令是否执行成功而非commandArray，从而永远无法调起commandArray
        ${cdCommand}
        if "${commandArray[@]}" >/dev/null 2>&1 & then
            formatSuccess "${serviceName}服务已成功调起，后台启动中，请稍后"
        else
            formatError "${serviceName}服务启动失败，请人工介入检查，以下是合成的调用命令："
            echo "${commandArray[@]}"
            formatWarningNoBlank "已跳过${serviceName}服务启动流程"
        fi
    done
}

# 两种停止方式的公用方法
StopService(){
    formatInfo "开始批量终止指定的所有服务"
    local serviceName pidList=() tempPidList=() retryServiceList=() tempRetryServiceList=() pid time
    for serviceName in "${needOperateServiceList[@]}" ; do
        mapfile -t tempPidList < <(pgrep -f "mcService=${serviceName}")
        if [ "${#tempPidList[@]}" -ne 0 ]; then
            retryServiceList=("${retryServiceList[@]}" "${serviceName}")
            pidList=("${pidList[@]}" "${tempPidList[@]}")
        fi
    done
#echo "pidList数量为${#pidList[@]}"
#echo "retryServiceList=${retryServiceList[*]}"
    for (( time=1; time<=retryTime; time++ )); do
        if [ "${#pidList[@]}" -eq 0 ]; then
            formatSuccess "指定的所有服务均未启动"
            break
        else
            for pid in "${pidList[@]}" ; do
                kill -9 "${pid}"
            done
        fi
        formatSuccess "终止命令已批量发送，已指定${gapSecond}秒的操作等待时间"
        sleep "${gapSecond}"

        formatInfo "正在检测是否存在残留进程"
        tempRetryServiceList=()
        for serviceName in "${retryServiceList[@]}" ; do
            mapfile -t pidList < <(pgrep -f "mcService=${serviceName}")
            if [ "${#pidList[@]}" -ne 0 ]; then
                tempRetryServiceList+=("${serviceName}")
            fi
            pidList=()
        done
        retryServiceList=("${tempRetryServiceList[@]}")

        if [ "${#retryServiceList[@]}" -ne 0 ]; then
            if [ "${time}" -lt "${retryTime}" ]; then
                formatError "以下服务终止失败，开始第${time}/${retryTime}次重试..."
                formatErrorNoBlank "${retryServiceList[@]}"
            elif [ "${time}" -eq "${retryTime}" ]; then
                formatError "以下服务终止失败的重试次数超限，请手动检查，跳过..."
                formatErrorNoBlank "${retryServiceList[@]}"
                break
            fi
        else
            formatSuccess "指定的所有服务已全部终止"
            break
        fi
#echo "现在的pidList=${pidList[*]}"
        for serviceName in "${retryServiceList[@]}" ; do
            mapfile -t -O "${#pidList[@]}" pidList < <(pgrep -f "mcService=${serviceName}")
        done
    done
}

OperationRoute(){
    case "${mainOperationName}" in
        "start")
            StartService
        ;;
        "stop")
            StopService
        ;;
        "restart")
            StopService
            StartService
        ;;
    esac
}

index=
case ${extraArgs[0]} in
    ""|"h"|"help"|"-h"|"--help")
        if [ -z "${extraArgs[1]}" ]; then
            OperationHelp
        else
            index=1
            InvalidParam ${index}
        fi
    ;;
    "all")
        if [ -z "${extraArgs[1]}" ]; then
            OperateUsingServiceStyle "${extraArgs[0]}"
            OperationRoute
        else
            index=1
            InvalidParam ${index}
        fi
    ;;
    "group")
        if [ -z "${extraArgs[1]}" ]; then
            extraArgs=("group")
            source ./flow/operation/ListOperation.sh
        else
            OperateUsingGroupStyle
            OperationRoute
        fi
    ;;
    *)
        OperateUsingServiceStyle
        OperationRoute
esac