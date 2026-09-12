import localUnitTest from './LocalUnit.test';
import logicUnitTest from './LogicUnitTest.test';

export default function testsuite() {
  localUnitTest();
  logicUnitTest();
}
