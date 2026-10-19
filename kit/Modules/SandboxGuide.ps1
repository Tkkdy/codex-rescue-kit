function New-SandboxGuide {
    [CmdletBinding()]param($Context,[string]$Target,[ValidateSet('legacy-windows','mxc','unknown')][string]$Backend='unknown',[string]$ErrorCode,[string]$ReviewedRulePath)
    Assert-Context $Context
    if(-not (Test-Path -LiteralPath $Context.output)){$null=New-PrivateDirectory $Context $Context.output}
    Assert-PrivateDirectory $Context $Context.output
    $path=Assert-PlainPath $Target -MustExist
    if(-not (Test-Within $path $Context.home)){throw 'SANDBOX_TARGET_OUTSIDE_HOME'}
    $snapshot=if($Context.fixture){$Context.facts.sandbox}else{
        $acl=Get-Acl -LiteralPath $path -ErrorAction Stop
        [pscustomobject]@{owner=$acl.Owner;sddl=$acl.Sddl;protected=$acl.AreAccessRulesProtected}
    }
    $private=Join-Path $Context.output ('sandbox-private-'+[guid]::NewGuid().ToString('N')+'.json')
    Write-DurableJson $private @{schema='rescue-sandbox-private-v2';target=$path;context=$Context.fingerprint;backend=$Backend;error_code=$ErrorCode;acl=$snapshot;observed_at=[DateTime]::UtcNow.ToString('o')}
    $matched=$false;$action='NO_ACL_CHANGE_RULE_AVAILABLE';$ruleHash=''
    if($ReviewedRulePath){
        $rule=Read-RescueJson $ReviewedRulePath;$ruleHash=Get-ShaFile $ReviewedRulePath
        # Rule is reviewed data, never an executable script. Only owner correction can be proposed;
        # DACL changes, recursive ownership changes, widening grants and disabling sandbox are unsupported.
        if($Backend -eq 'legacy-windows' -and $ErrorCode -ceq 'helper_sandbox_lock_failed' -and $rule.schema -eq 'rescue-reviewed-owner-rule-v2' -and $rule.backend -ceq $Backend -and $rule.target_relative -ceq $path.Substring($Context.home.Length+1) -and $rule.before_owner -ceq $snapshot.owner -and $rule.before_sddl_sha256 -ceq (Get-ShaText $snapshot.sddl) -and $rule.desired_owner -ceq $Context.identity -and $rule.change -ceq 'OWNER_ONLY_KEEP_DACL'){$matched=$true;$action='ADMIN_MANUAL_OWNER_ONLY_EXACT_TARGET_RULE_REQUIRES_SEPARATE_APPROVAL'}
    }
    $card=Join-Path $Context.output ('sandbox-guide-'+[guid]::NewGuid().ToString('N')+'.json')
    $data=@{schema='rescue-sandbox-guide-v2';status='BLOCKED';backend=$Backend;error_category=$(if($ErrorCode -ceq 'helper_sandbox_lock_failed'){$ErrorCode}else{'UNCLASSIFIED'});target_fingerprint=(Get-ShaText $path);owner_fingerprint=(Get-ShaText $snapshot.owner);sddl_sha256=(Get-ShaText $snapshot.sddl);private_snapshot=$private;rule_sha256=$ruleHash;precise_rule_matched=$matched;next_action=$action;steps=@('Review private target and exact before SDDL with administrator','If exact reviewed rule matches: approve only owner change for this single target in independent elevated host','Keep DACL unchanged; no recursive operations, grant widening or policy changes','Run SandboxGuide again after manual action and compare SDDL/owner','Collect real target Codex tool B evidence; host command alone is insufficient');manual_change=$(if($matched){@{target=$path;before_owner=$snapshot.owner;before_sddl_sha256=(Get-ShaText $snapshot.sddl);desired_owner=$Context.identity;change='OWNER_ONLY_KEEP_DACL';approval='SEPARATE_USER_ADMIN_APPROVAL_REQUIRED';execute_here=$false}}else{$null});automatic_acl_change=$false;exit_code=3}
    Write-DurableJson $card $data
    return [pscustomobject]$data
}
