#ifndef MLFS_COMMANDER_OPERATION_RESULT_H
#define MLFS_COMMANDER_OPERATION_RESULT_H

#include <QString>

struct OperationResult {
    bool ok = false;
    int code = 0;
    QString message;

    static OperationResult success(const QString& message = QString())
    {
        return {true, 0, message};
    }

    static OperationResult failure(int code, const QString& message)
    {
        return {false, code, message};
    }
};

#endif
