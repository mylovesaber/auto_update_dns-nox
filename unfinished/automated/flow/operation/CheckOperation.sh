#!/usr/bin/env bash
commonOutputString=
mainInfoOutputString=
excludeOutputString=
ShowParseCommonResult(){
    local javaVersionInfo preCommonOutputString
    javaVersionInfo=$(${javaCommand} -version 2>&1 | sed 's/^/  /g')
    preCommonOutputString="公共配置信息："
    if [ -z "${basePath}" ]; then
        commonOutputString="JAR包公共存放路径: 未指定"
    else
        commonOutputString="${commonOutputString}\nJAR包公共存放路径: ${basePath}"
    fi
    commonOutputString=$(echo -e "${commonOutputString}\njava程序绝对路径: ${javaCommand}\njava版本信息: " | column -t | sed 's/^/  /g')
    commonOutputString="${commonOutputString}\n${javaVersionInfo}\n\n"
    commonOutputString="${preCommonOutputString}\n${commonOutputString}"

}

ShowParseGroupResult(){
    local element outputString groupName
    # 汇总
    outputString="可控服务 所属分组 启动命令"
    for element in "${groupAndServiceChain[@]}"; do
        if [[ ${element} =~ "组" ]]; then
            outputString="${outputString}\nEMPTY_LINE\n"
            groupName="${element}"
        else
            outputString="${outputString}\n${element} ${groupName} COMMAND_${element}_LINE"
        fi
    done
    mainInfoOutputString=$(echo -e "${outputString}" | column -t | sed 's/EMPTY_LINE//g')
    for element in "${groupAndServiceChain[@]}"; do
        if [[ ! ${element} =~ "组" ]]; then
            mainInfoOutputString=${mainInfoOutputString//COMMAND_${element}_LINE/${cdCommand}';'${serviceAndCommandPair[${element}]}' >/dev/null 2>&1 &'}
        fi
    done
}

ShowExcludeServiceList(){
    excludeOutputString="\n\n已排除的服务列表：\n"
    local excludeIndex
    for excludeIndex in "${!excludeServiceList[@]}"; do
        if [[ ! ${excludeServiceList[${excludeIndex}]} =~ "组" ]]; then
            excludeOutputString="${excludeOutputString}\n${excludeServiceList[${excludeIndex}]}"
        else
            unset "excludeServiceList[${excludeIndex}]"
            continue
        fi
    done
}

MergeOutput(){
    echo -e "${commonOutputString}${mainInfoOutputString}${excludeOutputString}\n"
}

index=
case ${extraArgs[0]} in
    "")
        if [ -z "${extraArgs[1]}" ]; then
            ShowParseCommonResult
            ShowParseGroupResult
            ShowExcludeServiceList
            MergeOutput
        else
            index=1
            InvalidParam ${index}
        fi
    ;;
    "h"|"help"|"-h"|"--help")
        if [ -z "${extraArgs[1]}" ]; then
            OperationHelp
        else
            index=1
            InvalidParam ${index}
        fi
    ;;
    *)
        index=0
        InvalidParam ${index}
    ;;
esac

