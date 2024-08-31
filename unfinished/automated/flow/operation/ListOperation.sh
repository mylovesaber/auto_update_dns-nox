#!/usr/bin/env bash
ListGroupName(){
    local group
    formatInfo "以下是所有可控的服务组名："
    for group in "${groupNameList[@]}"; do
        echo "${group}"
    done
}

ListExcludeList(){
    local group
    formatInfo "以下是不受本工具管控的所有服务："
    for group in "${!excludeServiceList[@]}"; do
        if [ "${group}" -ne 0 ]; then
            echo "${excludeServiceList[${group}]}"
        fi
    done
}

ListServiceMin(){
    # 关联数组 serviceNameWithPID 无序，用有序的一维数组 groupAndServiceChain 做索引
    declare -A serviceNameWithPID
    local element getProcess outputString groupName

    for element in "${groupAndServiceChain[@]}"; do
#        echo "element值是${element}"
        if [[ ${element} =~ "组" ]]; then
            getProcess=""
        else
            getProcess=$(pgrep -f "mcService=${element}")
            if [ -z "${getProcess}" ]; then
                getProcess="未启动"
            else
                getProcess="运行中"
            fi
#            echo -e "getProcess值是${getProcess}\n"
            serviceNameWithPID[${element}]=${getProcess}
        fi
    done

    # 汇总
    outputString="服务名 所属分组 运行状态"
    groupName=
    for element in "${groupAndServiceChain[@]}"; do
        if [[ ${element} =~ "组" ]]; then
            outputString="${outputString}\nEMPTY_LINE"
            groupName="${element}"
        else
            outputString="${outputString}\n${element} ${groupName} ${serviceNameWithPID[$element]}"
        fi
    done
    echo -e "${outputString}" | column -t | sed 's/EMPTY_LINE//g'
}

ListServiceMax(){
    # 关联数组 serviceNameWithPID 和 serviceNameWithProcessCommand 无序，用有序的一维数组 groupAndServiceChain 做索引
    # getProcess 拆分成 servicePID 和 processCommand

    declare -A serviceNameWithPID serviceNameWithProcessCommand serviceNameWithPort
    local element getProcess outputString groupName servicePID servicePort processCommand

    for element in "${groupAndServiceChain[@]}"; do
#        echo "element值是${element}"
        if [[ ${element} =~ "组" ]]; then
            servicePID=""
            servicePort=""
            processCommand=("")
#            echo "进组"
        else
            getProcess=$(pgrep -af "mcService=${element}")
            if [ -z "${getProcess}" ]; then
                servicePID="未启动"
                servicePort="无"
                processCommand=("无")
            else
                servicePID=$(awk '{print $1}' <<< "${getProcess}")
                servicePort=$(ss -plnt | grep "${servicePID}" | awk '{ split($4, a, ":"); print a[length(a)] }' | xargs | tr ' ' ',')
                if [ -z "${servicePort}" ]; then
                    servicePort="无"
                fi
                mapfile -t processCommand < <(awk '{ for (i=2; i<=NF; i++) print $i }' <<< "${getProcess}")
            fi
        fi
#        echo -e "serviceNameWithPID值是${servicePID}"
#        echo -e "serviceNameWithProcessCommand值是${processCommand[*]}\n"
        serviceNameWithPID[${element}]=${servicePID}
        serviceNameWithPort[${element}]=${servicePort}
        serviceNameWithProcessCommand[${element}]=${processCommand[*]}
    done

    # 汇总
    outputString="服务名 所属分组 PID号 端口号 进程命令"
    groupName=
    for element in "${groupAndServiceChain[@]}"; do
        if [[ ${element} =~ "组" ]]; then
            outputString="${outputString}\nEMPTY_LINE\n"
            groupName="${element}"
        else
            outputString="${outputString}\n${element} ${groupName} ${serviceNameWithPID[$element]} ${serviceNameWithPort[$element]} PROCESS_${element}_LINE"
        fi
    done
    modOutput=$(echo -e "${outputString}" | column -t | sed 's/EMPTY_LINE//g')
    for element in "${groupAndServiceChain[@]}"; do
        if [[ ! ${element} =~ "组" ]]; then
            modOutput=${modOutput//PROCESS_${element}_LINE/${serviceNameWithProcessCommand[${element}]}}
        fi
    done
    echo -e "${modOutput}"
}


index=
case ${extraArgs[0]} in
    "")
        if [ -z "${extraArgs[1]}" ]; then
            ListServiceMin
        else
            index=1
            InvalidParam ${index}
        fi
    ;;
    "more")
        if [ -z "${extraArgs[1]}" ]; then
            ListServiceMax
        else
            index=1
            InvalidParam ${index}
        fi
    ;;
    "group")
        if [ -z "${extraArgs[1]}" ]; then
            ListGroupName
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
    "exclude")
        if [ -z "${extraArgs[1]}" ]; then
            ListExcludeList
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

